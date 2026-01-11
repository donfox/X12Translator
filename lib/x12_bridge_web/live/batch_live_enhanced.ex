defmodule X12BridgeWeb.BatchLiveEnhanced do
  @moduledoc """
  Enhanced Batch Processing page that supports:
  1. Web upload (database-backed)
  2. Remote import (HTTP/HTTPS)
  3. Real-time progress updates
  """
  use X12BridgeWeb, :live_view

  import X12BridgeWeb.Layouts, only: [app_layout: 1]

  alias X12Bridge.Conversions
  alias X12Bridge.Conversions.Batch
  alias X12Bridge.BatchProcessor
  alias X12Bridge.RemoteFetcher

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(X12Bridge.PubSub, "batches")
      Phoenix.PubSub.subscribe(X12Bridge.PubSub, "batch_processor")
    end

    batches = Conversions.list_batches(limit: 10)

    {:ok,
     socket
     |> assign(:current_path, "/converter")
     |> assign(:batches, batches)
     |> assign(:current_batch, nil)
     |> assign(:viewing_job_id, nil)  # Track which job's JSON is being viewed
     |> assign(:processing_mode, :upload)  # :upload, :hot_folder, or :remote_import
     |> assign(:hot_folder_status, nil)
     |> assign(:hot_folder_result, nil)
     |> assign(:remote_url, "")
     |> assign(:remote_status, nil)  # nil, :processing, :completed, :error
     |> assign(:remote_result, nil)
     |> assign(:processing_status, nil)  # NEW: Track active processing
     |> allow_upload(:batch_files,
         accept: [".x12", ".edi", ".txt", ".zip"],
         max_entries: 50,
         max_file_size: 10_000_000)}
  end

  # === HOT FOLDER EVENTS ===

  @impl true
  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_existing_atom(mode)
    {:noreply, assign(socket, :processing_mode, mode_atom)}
  end

  @impl true
  def handle_event("process_hot_folder", _params, socket) do
    # Process files from the hot folder
    Task.start(fn ->
      result = BatchProcessor.process_input_directory()
      Phoenix.PubSub.broadcast(
        X12Bridge.PubSub,
        "batch_processor",
        {:hot_folder_completed, result}
      )
    end)

    {:noreply,
     socket
     |> assign(:hot_folder_status, :processing)
     |> put_flash(:info, "Processing hot folder files...")}
  end

  @impl true
  def handle_event("process_test_batch_hot_folder", %{"batch_name" => batch_name}, socket) do
    # Process test batch using hot folder method
    Task.start(fn ->
      result = BatchProcessor.process_test_batch(batch_name)
      Phoenix.PubSub.broadcast(
        X12Bridge.PubSub,
        "batch_processor",
        {:hot_folder_completed, result}
      )
    end)

    {:noreply,
     socket
     |> assign(:hot_folder_status, :processing)
     |> put_flash(:info, "Processing test batch: #{batch_name}...")}
  end

  @impl true
  def handle_event("view_hot_folder_results", _params, socket) do
    # Open output directory in finder (Mac) or file explorer
    output_dir = "priv/batch_processing/output"

    case :os.type() do
      {:unix, :darwin} -> System.cmd("open", [output_dir])
      {:unix, _} -> System.cmd("xdg-open", [output_dir])
      {:win32, _} -> System.cmd("explorer", [output_dir])
      _ -> :ok
    end

    {:noreply, put_flash(socket, :info, "Opening output directory...")}
  end

  @impl true
  def handle_event("clear_hot_folder_result", _params, socket) do
    {:noreply,
     socket
     |> assign(:hot_folder_result, nil)
     |> assign(:hot_folder_status, nil)}
  end

  # === REMOTE IMPORT EVENTS ===

  @impl true
  def handle_event("update_remote_url", %{"url" => url}, socket) do
    {:noreply, assign(socket, :remote_url, url)}
  end

  @impl true
  def handle_event("update_remote_url", params, socket) do
    # Fallback for any unexpected param format
    url = params["url"] || params["value"] || ""
    {:noreply, assign(socket, :remote_url, url)}
  end

  @impl true
  def handle_event("process_remote_batch", %{"url" => source}, socket) do
    if String.trim(source) == "" do
      {:noreply, put_flash(socket, :error, "Please enter a source path or URL")}
    else
      # Spawn background task to fetch and process
      Task.start(fn ->
        case RemoteFetcher.fetch_and_extract(source) do
          {:ok, %{files: file_paths, temp_dir: temp_dir}} ->
            # Create batch in database
            {:ok, batch} =
              Conversions.create_batch(%{
                name: "Remote Import - #{extract_filename(source)}",
                total_files: length(file_paths)
              })

            Phoenix.PubSub.subscribe(X12Bridge.PubSub, "batch:#{batch.id}")

            # Create jobs and read file contents
            files_to_process =
              Enum.map(file_paths, fn path ->
                {:ok, content} = File.read(path)

                {:ok, job} =
                  Conversions.create_job(%{
                    batch_id: batch.id,
                    original_filename: Path.basename(path),
                    file_size: byte_size(content),
                    status: "pending"
                  })

                {job.id, content}
              end)

            # Process using existing pipeline
            Conversions.process_batch_sync(batch.id, files_to_process)

            # Cleanup temporary files
            RemoteFetcher.cleanup_temp_files(temp_dir)

            # Broadcast completion
            Phoenix.PubSub.broadcast(
              X12Bridge.PubSub,
              "batches",
              {:remote_import_completed, {:ok, batch}}
            )

          {:error, reason} ->
            Phoenix.PubSub.broadcast(
              X12Bridge.PubSub,
              "batches",
              {:remote_import_completed, {:error, reason}}
            )
        end
      end)

      {:noreply,
       socket
       |> assign(:remote_status, :processing)
       |> put_flash(:info, "Fetching and processing batch...")}
    end
  end

  @impl true
  def handle_event("clear_remote_result", _params, socket) do
    {:noreply,
     socket
     |> assign(:remote_result, nil)
     |> assign(:remote_status, nil)
     |> assign(:remote_url, "")}
  end

  # === DATABASE UPLOAD EVENTS (Original) ===

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :batch_files, ref)}
  end

  @impl true
  def handle_event("process_batch", _params, socket) do
    entries = socket.assigns.uploads.batch_files.entries

    if length(entries) == 0 do
      {:noreply, put_flash(socket, :error, "Please select files to upload")}
    else
      # Extract all files (including from ZIP files)
      all_files = extract_uploaded_files(socket)

      {:ok, batch} = Conversions.create_batch(%{
        name: "Batch Upload - #{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M")}",
        total_files: length(all_files)
      })

      Phoenix.PubSub.subscribe(X12Bridge.PubSub, "batch:#{batch.id}")

      # Create jobs and prepare files for processing
      files_to_process =
        Enum.map(all_files, fn {filename, content, file_size} ->
          {:ok, job} = Conversions.create_job(%{
            batch_id: batch.id,
            original_filename: filename,
            file_size: file_size,
            status: "pending"
          })

          {job.id, content}
        end)

      Task.start(fn ->
        Conversions.process_batch_sync(batch.id, files_to_process)
      end)

      batches = Conversions.list_batches(limit: 10)

      {:noreply,
       socket
       |> assign(:batches, batches)
       |> assign(:current_batch, batch)
       |> assign(:processing_status, :active)  # Mark as actively processing
       |> put_flash(:info, "Processing #{batch.total_files} files...")}
    end
  end

  @impl true
  def handle_event("view_batch", %{"id" => id}, socket) do
    batch = Conversions.get_batch!(id)
    {:noreply, assign(socket, :current_batch, batch)}
  end

  @impl true
  def handle_event("close_batch", _params, socket) do
    {:noreply,
     socket
     |> assign(:current_batch, nil)
     |> assign(:processing_status, nil)}  # Clear processing status when closing batch
  end

  @impl true
  def handle_event("dismiss_processing", _params, socket) do
    {:noreply, assign(socket, :processing_status, nil)}
  end

  @impl true
  def handle_event("clear_all_batches", _params, socket) do
    {:ok, count} = Conversions.delete_all_batches()
    batches = Conversions.list_batches(limit: 10)

    {:noreply,
     socket
     |> assign(:batches, batches)
     |> assign(:current_batch, nil)
     |> put_flash(:info, "Deleted #{count} batches successfully")}
  end

  @impl true
  def handle_event("view_job_json", %{"id" => job_id}, socket) do
    {:noreply, assign(socket, :viewing_job_id, job_id)}
  end

  @impl true
  def handle_event("hide_job_json", _params, socket) do
    {:noreply, assign(socket, :viewing_job_id, nil)}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("download_job", %{"id" => job_id}, socket) do
    job = Conversions.get_job!(job_id)

    if job.status == "completed" && job.json_result do
      {:noreply,
       socket
       |> push_event("download", %{
         filename: String.replace(job.original_filename, ~r/\.x12$/i, ".json"),
         content: job.json_result
       })}
    else
      {:noreply, put_flash(socket, :error, "Job not completed or has no result")}
    end
  end

  @impl true
  def handle_event("download_batch_zip", %{"id" => batch_id}, socket) do
    batch = Conversions.get_batch!(batch_id)

    # Get all completed jobs with JSON results
    completed_jobs =
      batch.jobs
      |> Enum.filter(fn job -> job.status == "completed" && job.json_result end)

    if length(completed_jobs) == 0 do
      {:noreply, put_flash(socket, :error, "No completed conversions to download")}
    else
      # Create list of files for ZIP archive
      # Format: [{filename, content}, ...]
      files =
        Enum.map(completed_jobs, fn job ->
          json_filename = String.replace(job.original_filename, ~r/\.(x12|edi|txt)$/i, ".json")
          {String.to_charlist(json_filename), job.json_result}
        end)

      # Create ZIP in memory
      case :zip.create("batch_results.zip", files, [:memory]) do
        {:ok, {"batch_results.zip", zip_binary}} ->
          # Convert binary to base64 for download
          zip_base64 = Base.encode64(zip_binary)

          {:noreply,
           socket
           |> push_event("download_zip", %{
             filename: "#{sanitize_batch_name(batch.name)}.zip",
             content: zip_base64
           })}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to create ZIP: #{inspect(reason)}")}
      end
    end
  end

  # === PUBSUB HANDLERS ===

  @impl true
  def handle_info({:job_completed, _job_id, _status}, socket) do
    batch = if socket.assigns.current_batch do
      Conversions.get_batch!(socket.assigns.current_batch.id)
    else
      nil
    end

    batches = Conversions.list_batches(limit: 10)

    {:noreply,
     socket
     |> assign(:batches, batches)
     |> assign(:current_batch, batch)}
  end

  @impl true
  def handle_info({:batch_completed, batch_id}, socket) do
    batch = Conversions.get_batch!(batch_id)
    batches = Conversions.list_batches(limit: 10)

    {:noreply,
     socket
     |> assign(:batches, batches)
     |> assign(:current_batch, batch)
     |> assign(:processing_status, :completed)  # Mark as completed
     |> put_flash(:info, "Batch completed! #{batch.completed_files} successful, #{batch.failed_files} failed")}
  end

  @impl true
  def handle_info({:hot_folder_completed, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:hot_folder_status, :completed)
     |> assign(:hot_folder_result, result)
     |> put_flash(:info, "Hot folder processing complete! #{result.successful_files}/#{result.total_files} successful")}
  end

  @impl true
  def handle_info({:hot_folder_completed, {:error, :no_files}}, socket) do
    {:noreply,
     socket
     |> assign(:hot_folder_status, :no_files)
     |> put_flash(:info, "No files found in input directory")}
  end

  @impl true
  def handle_info({:remote_import_completed, {:ok, batch}}, socket) do
    batches = Conversions.list_batches(limit: 10)

    {:noreply,
     socket
     |> assign(:batches, batches)
     |> assign(:remote_status, :completed)
     |> assign(:remote_result, batch)
     |> assign(:current_batch, batch)
     |> put_flash(:info, "Remote import complete! #{batch.completed_files} successful, #{batch.failed_files} failed")}
  end

  @impl true
  def handle_info({:remote_import_completed, {:error, reason}}, socket) do
    error_message = format_remote_error(reason)

    {:noreply,
     socket
     |> assign(:remote_status, :error)
     |> put_flash(:error, error_message)}
  end

  # === RENDER ===

  @impl true
  def render(assigns) do
    ~H"""
    <.app_layout flash={@flash} current_path={@current_path}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-white">X12 EDI Converter</h1>
          <p class="mt-2 text-gray-300">
            Convert 1-50 X12 files using web upload or remote URL
          </p>
        </div>

        <!-- Mode Switcher -->
        <div class="mb-6 bg-gray-800 rounded-lg p-4">
          <div class="flex items-center gap-4">
            <span class="text-white font-medium">Processing Mode:</span>
            <div class="flex gap-2">
              <button
                phx-click="switch_mode"
                phx-value-mode="upload"
                class={"px-4 py-2 rounded-md transition " <> if @processing_mode == :upload, do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600"}
              >
                📤 Web Upload
              </button>
              <button
                phx-click="switch_mode"
                phx-value-mode="remote_import"
                class={"px-4 py-2 rounded-md transition " <> if @processing_mode == :remote_import, do: "bg-purple-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600"}
              >
                🌐 Remote Import (HTTP/HTTPS)
              </button>
            </div>
          </div>
        </div>

        <!-- PROCESSING STATUS INDICATOR -->
        <%= if @processing_status == :active && @current_batch do %>
          <div class="mb-6 bg-blue-50 border-2 border-blue-200 rounded-lg p-6">
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-lg font-bold text-blue-900">🔄 Processing Files...</h3>
              <button
                phx-click="dismiss_processing"
                class="text-blue-600 hover:text-blue-800 text-sm font-medium"
                title="Dismiss (processing continues in background)"
              >
                Dismiss
              </button>
            </div>
            <div class="flex items-center gap-4">
              <svg class="animate-spin h-8 w-8 text-blue-600 flex-shrink-0" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              <div class="flex-1">
                <p class="text-sm text-blue-700 font-medium">
                  <%= @current_batch.completed_files + @current_batch.failed_files %> of <%= @current_batch.total_files %> files processed
                </p>
                <% completed = @current_batch.completed_files %>
                <% failed = @current_batch.failed_files %>
                <%= if completed > 0 || failed > 0 do %>
                  <p class="text-xs text-blue-600 mt-1">
                    <span class="text-green-600 font-medium"><%= completed %> successful</span>
                    <%= if failed > 0 do %>
                      · <span class="text-red-600 font-medium"><%= failed %> failed</span>
                    <% end %>
                  </p>
                <% end %>
                <div class="mt-3 bg-blue-200 rounded-full h-3">
                  <div
                    class="bg-blue-600 h-3 rounded-full transition-all duration-500"
                    style={"width: #{Batch.progress_percentage(@current_batch)}%"}
                  >
                  </div>
                </div>
              </div>
              <div class="text-right flex-shrink-0">
                <div class="text-3xl font-bold text-blue-900">
                  <%= Batch.progress_percentage(@current_batch) %>%
                </div>
                <div class="text-xs text-blue-600">Complete</div>
              </div>
            </div>
            <div class="mt-3 text-xs text-blue-600">
              💡 Tip: Files are processed with 30-second timeout protection. The app will never freeze.
            </div>
          </div>
        <% end %>

        <!-- PROCESSING COMPLETED INDICATOR -->
        <%= if @processing_status == :completed && @current_batch do %>
          <div class="mb-6 bg-green-50 border-2 border-green-200 rounded-lg p-6">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-4">
                <svg class="h-8 w-8 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <div>
                  <h3 class="text-lg font-bold text-green-900">✅ Processing Complete!</h3>
                  <p class="text-sm text-green-700">
                    <%= @current_batch.completed_files %> successful · <%= @current_batch.failed_files %> failed · <%= @current_batch.total_files %> total
                  </p>
                </div>
              </div>
              <button
                phx-click="dismiss_processing"
                class="px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700"
              >
                Dismiss
              </button>
            </div>
          </div>
        <% end %>

        <!-- WEB UPLOAD MODE -->
        <%= if @processing_mode == :upload do %>
          <div class="mb-8 bg-white shadow rounded-lg p-6">
            <div class="mb-4">
              <h2 class="text-xl font-semibold text-gray-900">Upload Files</h2>
              <p class="text-sm text-gray-500">Upload individual files or ZIP archives containing multiple X12 files</p>
            </div>

            <form phx-submit="process_batch" phx-change="validate_upload" class="space-y-4">
                <div class="border-2 border-dashed border-gray-300 rounded-lg p-6" phx-drop-target={@uploads.batch_files.ref}>
                  <.live_file_input upload={@uploads.batch_files} class="hidden" />
                  <label
                    for={@uploads.batch_files.ref}
                    class="cursor-pointer flex flex-col items-center"
                  >
                    <svg class="w-12 h-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
                    </svg>
                    <p class="mt-2 text-sm text-gray-600">
                      Click to select or drag and drop files
                    </p>
                    <p class="mt-1 text-xs text-gray-500">
                      X12, EDI, TXT, or ZIP files (up to 50 files, 10MB each)
                    </p>
                    <p class="mt-1 text-xs text-gray-400">
                      ZIP files will be automatically extracted
                    </p>
                  </label>

                  <div :for={entry <- @uploads.batch_files.entries} class="mt-4 p-3 bg-green-50 border border-green-200 rounded-lg">
                    <div class="flex justify-between items-center">
                      <div class="flex-1">
                        <span class="text-base font-semibold text-gray-900"><%= entry.client_name %></span>
                        <span class="text-sm text-gray-600 ml-3"><%= format_bytes(entry.client_size) %></span>
                      </div>
                      <button
                        type="button"
                        phx-click="cancel_upload"
                        phx-value-ref={entry.ref}
                        class="ml-4 px-3 py-1 bg-red-100 text-red-700 rounded hover:bg-red-200 transition-colors flex items-center gap-1"
                        title="Remove this file"
                      >
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                        </svg>
                        Remove
                      </button>
                    </div>

                    <!-- Upload progress bar (if uploading) -->
                    <%= if entry.progress > 0 && entry.progress < 100 do %>
                      <div class="mt-2 bg-green-200 rounded-full h-2">
                        <div
                          class="bg-green-600 h-2 rounded-full transition-all duration-300"
                          style={"width: #{entry.progress}%"}
                        >
                        </div>
                      </div>
                      <p class="text-xs text-green-600 mt-1">Uploading... <%= entry.progress %>%</p>
                    <% end %>

                    <!-- Error display -->
                    <%= for err <- upload_errors(@uploads.batch_files, entry) do %>
                      <p class="mt-2 text-sm text-red-600">
                        ⚠️ <%= error_to_string(err) %>
                      </p>
                    <% end %>
                  </div>
                </div>

                <%= if length(@uploads.batch_files.entries) > 0 do %>
                  <button
                    type="submit"
                    class="w-full px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700"
                  >
                    Process <%= length(@uploads.batch_files.entries) %> Files
                  </button>
                <% end %>
              </form>
          </div>

          <!-- Batches List -->
          <div class="bg-white shadow rounded-lg p-6">
            <div class="flex justify-between items-center mb-4">
              <h2 class="text-xl font-semibold text-gray-900">Recent Batches</h2>
              <%= if length(@batches) > 0 do %>
                <button
                  phx-click="clear_all_batches"
                  data-confirm="Are you sure you want to delete ALL batches? This cannot be undone."
                  class="group flex items-center gap-2 px-4 py-2 bg-red-50 text-red-700 font-medium rounded-lg border border-red-200 hover:bg-red-100 hover:border-red-300 transition-all duration-200 shadow-sm hover:shadow"
                >
                  <svg class="w-4 h-4 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                  Clear All Batches
                </button>
              <% end %>
            </div>

            <%= if length(@batches) == 0 do %>
              <p class="text-gray-500 text-center py-8">No batches yet. Upload files to get started!</p>
            <% else %>
              <div class="space-y-4">
                <%= for batch <- @batches do %>
                  <div class="border border-gray-200 rounded-lg p-4 hover:shadow-md transition">
                    <div class="flex justify-between items-start">
                      <div class="flex-1">
                        <h3 class="font-medium text-gray-900"><%= batch.name %></h3>
                        <p class="text-sm text-gray-500">
                          <%= Calendar.strftime(batch.inserted_at, "%Y-%m-%d %H:%M") %>
                        </p>
                      </div>
                      <div class="flex items-center gap-4">
                        <div class="text-right">
                          <div class="text-sm">
                            <span class="text-green-600 font-medium"><%= batch.completed_files %></span> /
                            <span class="text-red-600"><%= batch.failed_files %></span> /
                            <span class="text-gray-600"><%= batch.total_files %></span>
                          </div>
                          <div class="text-xs text-gray-500">Success / Failed / Total</div>
                        </div>
                        <div class="flex gap-2">
                          <%= if batch.completed_files > 0 do %>
                            <button
                              phx-click="download_batch_zip"
                              phx-value-id={batch.id}
                              class="px-3 py-1 bg-green-100 text-green-700 rounded hover:bg-green-200 flex items-center gap-1"
                              title="Download all successful conversions as ZIP"
                            >
                              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                              </svg>
                              ZIP
                            </button>
                          <% end %>
                          <button
                            phx-click="view_batch"
                            phx-value-id={batch.id}
                            class="px-3 py-1 bg-blue-100 text-blue-700 rounded hover:bg-blue-200"
                          >
                            View
                          </button>
                        </div>
                      </div>
                    </div>

                    <div class="mt-3 bg-gray-200 rounded-full h-2">
                      <div
                        class="bg-blue-600 h-2 rounded-full transition-all duration-500"
                        style={"width: #{Batch.progress_percentage(batch)}%"}
                      >
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>

        <!-- REMOTE IMPORT MODE -->
        <%= if @processing_mode == :remote_import do %>
          <div class="mb-8 bg-white shadow rounded-lg p-6">
            <h2 class="text-xl font-semibold text-gray-900 mb-4">Remote Batch Import</h2>
            <p class="text-sm text-gray-600 mb-6">
              Fetch and process X12 files from multiple sources
            </p>

            <form phx-submit="process_remote_batch" class="space-y-4">
              <div>
                <label for="remote-url" class="block text-sm font-medium text-gray-700 mb-2">
                  ZIP File Source
                </label>
                <input
                  type="text"
                  id="remote-url"
                  name="url"
                  value={@remote_url}
                  phx-keyup="update_remote_url"
                  placeholder="https://example.com/batch.zip or /path/to/batch.zip or /mnt/data/x12/batch.zip"
                  class="w-full px-4 py-2 border border-gray-300 rounded-md focus:ring-purple-500 focus:border-purple-500"
                />
                <p class="mt-2 text-xs text-gray-500">
                  Supports: HTTP/HTTPS URLs • Local file paths • Databricks paths (/mnt/...)
                </p>
              </div>

              <button
                type="submit"
                disabled={@remote_status == :processing}
                class="w-full px-4 py-2 bg-purple-600 text-white rounded-md hover:bg-purple-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <%= if @remote_status == :processing, do: "⏳ Downloading and Processing...", else: "🚀 Fetch & Process" %>
              </button>
            </form>

            <!-- Remote Processing Status -->
            <%= if @remote_status == :processing do %>
              <div class="mt-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
                <div class="flex items-center gap-3">
                  <svg class="animate-spin h-5 w-5 text-blue-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  <div>
                    <p class="font-semibold text-blue-900">Downloading and processing...</p>
                    <p class="text-sm text-blue-700">This may take a moment depending on file size</p>
                  </div>
                </div>
              </div>
            <% end %>

            <!-- Remote Results -->
            <%= if @remote_result do %>
              <div class="mt-6 p-4 bg-green-50 border border-green-200 rounded-lg">
                <div class="flex justify-between items-start mb-4">
                  <h3 class="font-semibold text-green-900">✓ Remote Import Complete</h3>
                  <button
                    phx-click="clear_remote_result"
                    class="text-green-700 hover:text-green-900"
                  >
                    ✕
                  </button>
                </div>

                <div class="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <span class="text-gray-600">Batch Name:</span>
                    <span class="ml-2 font-semibold"><%= @remote_result.name %></span>
                  </div>
                  <div>
                    <span class="text-gray-600">Total Files:</span>
                    <span class="ml-2 font-semibold"><%= @remote_result.total_files %></span>
                  </div>
                  <div>
                    <span class="text-gray-600">Successful:</span>
                    <span class="ml-2 font-semibold text-green-600"><%= @remote_result.completed_files %></span>
                  </div>
                  <div>
                    <span class="text-gray-600">Failed:</span>
                    <span class="ml-2 font-semibold text-red-600"><%= @remote_result.failed_files %></span>
                  </div>
                </div>

                <button
                  phx-click="view_batch"
                  phx-value-id={@remote_result.id}
                  class="mt-4 w-full px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700"
                >
                  View Batch Details
                </button>
              </div>
            <% end %>

            <!-- Info Box -->
            <div class="mt-6 p-4 bg-purple-50 border border-purple-200 rounded-lg text-sm">
              <h4 class="font-semibold text-purple-900 mb-2">ℹ️ How it works:</h4>
              <ul class="space-y-1 text-purple-800 text-xs">
                <li>1. Enter a URL pointing to a ZIP archive containing X12 files</li>
                <li>2. The ZIP is downloaded and extracted to a temporary directory</li>
                <li>3. All X12 files (.x12, .edi, .txt) are processed concurrently</li>
                <li>4. Results are stored in the database and can be downloaded</li>
                <li>5. Temporary files are automatically cleaned up</li>
              </ul>
              <div class="mt-3 pt-3 border-t border-purple-200">
                <p class="text-purple-900 font-medium">Limits:</p>
                <p class="text-purple-800 text-xs">Max file size: 100 MB | Timeout: 60 seconds</p>
              </div>
            </div>

            <!-- Database Batches List (shared with upload mode) -->
            <div class="mt-8 pt-8 border-t border-gray-200">
              <div class="flex justify-between items-center mb-4">
                <h3 class="text-lg font-semibold text-gray-900">Recent Remote Imports</h3>
                <%= if length(@batches) > 0 do %>
                  <button
                    phx-click="clear_all_batches"
                    data-confirm="Are you sure you want to delete ALL batches? This cannot be undone."
                    class="group flex items-center gap-2 px-4 py-2 bg-red-50 text-red-700 font-medium rounded-lg border border-red-200 hover:bg-red-100 hover:border-red-300 transition-all duration-200 shadow-sm hover:shadow"
                  >
                    <svg class="w-4 h-4 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                    Clear All Batches
                  </button>
                <% end %>
              </div>
              <%= if length(@batches) == 0 do %>
                <p class="text-gray-500 text-center py-8">No remote imports yet. Enter a URL to get started!</p>
              <% else %>
                <div class="space-y-4">
                  <%= for batch <- Enum.filter(@batches, fn b -> String.starts_with?(b.name, "Remote Import") end) do %>
                    <div class="border border-gray-200 rounded-lg p-4 hover:shadow-md transition">
                      <div class="flex justify-between items-start">
                        <div class="flex-1">
                          <h3 class="font-medium text-gray-900"><%= batch.name %></h3>
                          <p class="text-sm text-gray-500">
                            <%= Calendar.strftime(batch.inserted_at, "%Y-%m-%d %H:%M") %>
                          </p>
                        </div>
                        <div class="flex items-center gap-4">
                          <div class="text-right">
                            <div class="text-sm">
                              <span class="text-green-600 font-medium"><%= batch.completed_files %></span> /
                              <span class="text-red-600"><%= batch.failed_files %></span> /
                              <span class="text-gray-600"><%= batch.total_files %></span>
                            </div>
                            <div class="text-xs text-gray-500">Success / Failed / Total</div>
                          </div>
                          <div class="flex gap-2">
                            <%= if batch.completed_files > 0 do %>
                              <button
                                phx-click="download_batch_zip"
                                phx-value-id={batch.id}
                                class="px-3 py-1 bg-green-100 text-green-700 rounded hover:bg-green-200 flex items-center gap-1"
                                title="Download all successful conversions as ZIP"
                              >
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                                </svg>
                                ZIP
                              </button>
                            <% end %>
                            <button
                              phx-click="view_batch"
                              phx-value-id={batch.id}
                              class="px-3 py-1 bg-purple-100 text-purple-700 rounded hover:bg-purple-200"
                            >
                              View
                            </button>
                          </div>
                        </div>
                      </div>

                      <div class="mt-3 bg-gray-200 rounded-full h-2">
                        <div
                          class="bg-purple-600 h-2 rounded-full transition-all duration-500"
                          style={"width: #{Batch.progress_percentage(batch)}%"}
                        >
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Batch Detail Modal (for database batches) -->
        <%= if @current_batch do %>
          <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50" phx-click="close_batch">
            <div class="bg-white rounded-lg max-w-4xl w-full max-h-[90vh] overflow-hidden flex flex-col" phx-click="stop_propagation">
              <div class="p-6 border-b flex justify-between items-center">
                <div>
                  <h2 class="text-2xl font-bold text-gray-900"><%= @current_batch.name %></h2>
                  <p class="text-sm text-gray-500">
                    <%= @current_batch.completed_files + @current_batch.failed_files %> / <%= @current_batch.total_files %> processed
                  </p>
                </div>
                <button
                  phx-click="close_batch"
                  class="text-gray-400 hover:text-gray-600"
                >
                  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>

              <div class="flex-1 overflow-y-auto p-6">
                <div class="space-y-3">
                  <%= for job <- @current_batch.jobs do %>
                    <div class="border border-gray-200 rounded-lg p-4">
                      <div class="flex justify-between items-center">
                        <div class="flex-1">
                          <h4 class="font-medium text-gray-900"><%= job.original_filename %></h4>
                          <p class="text-sm text-gray-500"><%= format_bytes(job.file_size) %></p>
                        </div>
                        <div class="flex items-center gap-3">
                          <span class={"px-3 py-1 rounded-full text-sm " <> status_class(job.status)}>
                            <%= String.upcase(job.status) %>
                          </span>
                          <%= if job.status == "completed" do %>
                            <button
                              phx-click={if @viewing_job_id == to_string(job.id), do: "hide_job_json", else: "view_job_json"}
                              phx-value-id={job.id}
                              class="px-3 py-1 bg-blue-100 text-blue-700 rounded hover:bg-blue-200"
                            >
                              <%= if @viewing_job_id == to_string(job.id), do: "Hide Comparison", else: "View Side-by-Side" %>
                            </button>
                            <button
                              phx-click="download_job"
                              phx-value-id={job.id}
                              class="px-3 py-1 bg-green-100 text-green-700 rounded hover:bg-green-200"
                            >
                              Download JSON
                            </button>
                          <% end %>
                        </div>
                      </div>
                      <%= if job.error_message do %>
                        <div class="mt-2 p-2 bg-red-50 text-red-700 text-sm rounded">
                          <%= job.error_message %>
                        </div>
                      <% end %>
                    </div>

                    <!-- Side-by-Side Comparison Viewer Section -->
                    <%= if @viewing_job_id == to_string(job.id) && job.json_result do %>
                      <div class="mt-2 mx-4 mb-3 bg-gray-50 p-4 rounded border border-gray-300">
                        <div class="flex justify-between items-center mb-3">
                          <h5 class="text-sm font-medium text-gray-700">Side-by-Side Comparison:</h5>
                          <button
                            phx-click="hide_job_json"
                            class="text-xs text-blue-600 hover:text-blue-800 underline"
                          >
                            Hide
                          </button>
                        </div>
                        <div class="grid grid-cols-2 gap-4">
                          <!-- X12 Content (Left) -->
                          <div class="flex flex-col">
                            <h6 class="text-xs font-semibold text-gray-600 mb-2 bg-gray-200 p-2 rounded">Original X12 File:</h6>
                            <pre class="bg-white p-4 rounded border border-gray-200 overflow-x-auto text-black text-sm font-mono max-h-[600px] overflow-y-auto flex-1" style="color: black !important;"><%= job.x12_content || "X12 content not available" %></pre>
                          </div>
                          <!-- JSON Output (Right) -->
                          <div class="flex flex-col">
                            <h6 class="text-xs font-semibold text-gray-600 mb-2 bg-gray-200 p-2 rounded">Converted JSON:</h6>
                            <pre class="bg-white p-4 rounded border border-gray-200 overflow-x-auto text-black text-sm font-mono max-h-[600px] overflow-y-auto flex-1" style="color: black !important;"><%= job.json_result %></pre>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </.app_layout>
    """
  end

  # === ZIP FILE HANDLING ===

  defp extract_uploaded_files(socket) do
    consume_uploaded_entries(socket, :batch_files, fn %{path: path}, entry ->
      if is_zip_file?(entry.client_name) do
        # Extract files from ZIP
        extract_zip_file(path)
      else
        # Regular file - just read it
        {:ok, content} = File.read(path)
        [{entry.client_name, content, entry.client_size}]
      end
    end)
    |> List.flatten()
  end

  defp is_zip_file?(filename) do
    String.ends_with?(String.downcase(filename), ".zip")
  end

  defp extract_zip_file(zip_path) do
    # Create a temporary directory for extraction
    temp_dir = Path.join(System.tmp_dir!(), "x12_zip_#{:rand.uniform(999999)}")
    File.mkdir_p!(temp_dir)

    try do
      # Extract ZIP file
      case :zip.unzip(String.to_charlist(zip_path), cwd: String.to_charlist(temp_dir)) do
        {:ok, extracted_files} ->
          # Read all extracted files
          extracted_files
          |> Enum.map(&to_string/1)
          |> Enum.filter(fn file ->
            # Only process X12/EDI files, skip directories and other files
            !File.dir?(file) && Regex.match?(~r/\.(x12|edi|txt)$/i, file)
          end)
          |> Enum.map(fn file ->
            {:ok, content} = File.read(file)
            filename = Path.basename(file)
            file_size = byte_size(content)
            {filename, content, file_size}
          end)

        {:error, reason} ->
          # If ZIP extraction fails, return empty list
          IO.puts("Failed to extract ZIP: #{inspect(reason)}")
          []
      end
    after
      # Clean up temporary directory
      File.rm_rf(temp_dir)
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp sanitize_batch_name(name) do
    # Remove special characters and spaces, replace with underscores
    name
    |> String.replace(~r/[^a-zA-Z0-9\-_]/, "_")
    |> String.slice(0..50)  # Limit length
  end

  defp status_class("completed"), do: "bg-green-100 text-green-800"
  defp status_class("failed"), do: "bg-red-100 text-red-800"
  defp status_class("processing"), do: "bg-blue-100 text-blue-800"
  defp status_class("pending"), do: "bg-gray-100 text-gray-800"
  defp status_class(_), do: "bg-gray-100 text-gray-800"

  defp extract_filename(url) do
    url
    |> URI.parse()
    |> Map.get(:path, "")
    |> Path.basename()
  end

  defp format_remote_error(:invalid_url), do: "Invalid source. Please enter a valid HTTP/HTTPS URL, local file path, or Databricks path."
  defp format_remote_error(:invalid_path), do: "File not found. Please check the file path and try again."
  defp format_remote_error(:download_failed), do: "Failed to download file. Please check the URL and try again."
  defp format_remote_error({:http_error, 404}), do: "File not found (404). Please verify the URL."
  defp format_remote_error({:http_error, 500}), do: "Server error (500). Please try again later."
  defp format_remote_error({:http_error, status}), do: "HTTP error (#{status}). Please try again."
  defp format_remote_error(:timeout), do: "Download timed out. The file may be too large or the server is slow."
  defp format_remote_error(:invalid_zip), do: "Invalid ZIP file. Please ensure the file is a valid ZIP archive."
  defp format_remote_error(:no_x12_files), do: "No X12 files found in ZIP. Expected .x12, .edi, or .txt files."
  defp format_remote_error(:file_too_large), do: "File exceeds maximum size of 100MB."
  defp format_remote_error(:databricks_not_configured), do: "Databricks is not configured. Please set DATABRICKS_HOST and DATABRICKS_TOKEN environment variables."
  defp format_remote_error({:databricks_error, status}), do: "Databricks API error (#{status}). Please check your credentials and path."
  defp format_remote_error(:invalid_databricks_response), do: "Invalid response from Databricks API. Please check the file path."
  defp format_remote_error(_), do: "An error occurred while processing the file."

  # Convert upload errors to human-readable strings
  defp error_to_string(:too_large), do: "File is too large (max 10MB)"
  defp error_to_string(:not_accepted), do: "File type not accepted (use .x12, .edi, .txt, or .zip)"
  defp error_to_string(:too_many_files), do: "Too many files (max 50)"
  defp error_to_string(:external_client_failure), do: "Upload failed - please try again"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"
end
