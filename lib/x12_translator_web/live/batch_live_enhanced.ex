defmodule X12TranslatorWeb.BatchLiveEnhanced do
  @moduledoc """
  Enhanced Batch Processing page that supports:
  1. Web upload (database-backed)
  2. Remote import (HTTP/HTTPS/local files)
  3. Real-time progress updates
  """
  use X12TranslatorWeb, :live_view

  require Logger

  import X12TranslatorWeb.Layouts, only: [app_layout: 1]

  alias X12Translator.Conversions
  alias X12Translator.Conversions.Batch
  alias X12Translator.BatchProcessor
  alias X12Translator.RemoteFetcher
  alias X12Translator.UploadDirs

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(X12Translator.PubSub, "batches")
      Phoenix.PubSub.subscribe(X12Translator.PubSub, "batch_processor")
    end

    batches = Conversions.list_batches(limit: 10)

    {:ok,
     socket
     |> assign(:current_path, "/converter")
     |> assign(:batches, batches)
     |> assign(:current_batch, nil)
     # Track which job's JSON is being viewed
     |> assign(:viewing_job_id, nil)
     # :upload or :remote_import
     |> assign(:processing_mode, :upload)
     # nil, :processing, :completed, :error
     |> assign(:remote_status, nil)
     |> assign(:remote_result, nil)
     # Track active processing
     |> assign(:processing_status, nil)
     # Store uploaded file contents for verification/translation
     |> assign(:uploaded_files, %{})
     # User name for batch association
     |> assign(:submitted_by, "")
     # Remote URL field value (preserved across re-renders)
     |> assign(:remote_url, "")
     # SFTP credential fields (shown when URL starts with sftp://)
     |> assign(:show_sftp_fields, false)
     |> assign(:sftp_username, "")
     |> assign(:sftp_password, "")
     |> assign(:sftp_port, "22")
     |> allow_upload(:batch_files,
       accept: [".x12", ".edi", ".txt", ".zip"],
       max_entries: 50,
       max_file_size: 10_000_000
     )}
  end

  # === MODE SWITCHING ===

  @impl true
  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_existing_atom(mode)
    {:noreply, assign(socket, :processing_mode, mode_atom)}
  end

  @impl true
  def handle_event("update_submitted_by", %{"value" => value}, socket) do
    {:noreply, assign(socket, :submitted_by, value || "")}
  end

  # === REMOTE IMPORT EVENTS ===

  @impl true
  def handle_event("url_changed", %{"value" => url}, socket) do
    url = url || ""
    show_sftp = String.starts_with?(String.downcase(url), "sftp://")

    {:noreply,
     socket
     |> assign(:remote_url, url)
     |> assign(:show_sftp_fields, show_sftp)}
  end

  # Fallback for form change events
  def handle_event("url_changed", params, socket) do
    url = params["url"] || params["value"] || ""
    show_sftp = String.starts_with?(String.downcase(url), "sftp://")

    {:noreply,
     socket
     |> assign(:remote_url, url)
     |> assign(:show_sftp_fields, show_sftp)}
  end

  @impl true
  def handle_event("update_sftp_field", params, socket) do
    field = params["field"]
    value = params["value"] || ""
    field_atom = String.to_existing_atom("sftp_#{field}")
    {:noreply, assign(socket, field_atom, value)}
  end

  @impl true
  def handle_event("process_remote_batch", params, socket) do
    require Logger
    Logger.info("PROCESS_REMOTE_BATCH params: #{inspect(Map.keys(params))}")

    source = params["url"] || ""

    if String.trim(source) == "" do
      {:noreply, put_flash(socket, :error, "Please enter a source path or URL")}
    else
      # Build SFTP options if this is an SFTP URL
      # Read credentials from form params directly (more reliable than assigns)
      sftp_opts =
        if String.starts_with?(String.downcase(source), "sftp://") do
          username = params["sftp_username"] || socket.assigns.sftp_username || ""
          password = params["sftp_password"] || socket.assigns.sftp_password || ""
          port_str = params["sftp_port"] || socket.assigns.sftp_port || "22"
          port = if port_str == "", do: 22, else: String.to_integer(port_str)

          Logger.info(
            "SFTP credentials - user: #{username}, pass length: #{String.length(password)}, port: #{port}"
          )

          [
            sftp_username: username,
            sftp_password: password,
            sftp_port: port
          ]
        else
          []
        end

      # Capture submitted_by before spawning task
      submitted_by = socket.assigns.submitted_by

      # Spawn background task to fetch and process
      Task.start(fn ->
        case RemoteFetcher.fetch_and_extract(source, sftp_opts) do
          {:ok, %{files: file_paths, temp_dir: temp_dir}} ->
            {input_dir, output_dir} = UploadDirs.ensure(submitted_by)

            {copied_files, metadata} =
              copy_files_to_input(file_paths, source, input_dir)

            batch_opts = %{
              input_dir: input_dir,
              output_dir: output_dir,
              batch_name: "Remote Import - #{extract_filename(source)}",
              file_metadata: metadata,
              submitted_by: String.trim(submitted_by)
            }

            result =
              case copied_files do
                [] -> {:error, :no_x12_files}
                _ -> BatchProcessor.process_input_directory(batch_opts)
              end

            RemoteFetcher.cleanup_temp_files(temp_dir)

            case result do
              {:ok, batch_result} ->
                Phoenix.PubSub.broadcast(
                  X12Translator.PubSub,
                  "batches",
                  {
                    :remote_import_completed,
                    {:ok, batch_result.batch_record},
                    batch_result.output_summary,
                    output_dir
                  }
                )

              {:error, reason} ->
                Phoenix.PubSub.broadcast(
                  X12Translator.PubSub,
                  "batches",
                  {:remote_import_completed, {:error, reason}}
                )
            end

          {:error, reason} ->
            Phoenix.PubSub.broadcast(
              X12Translator.PubSub,
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
     |> assign(:remote_status, nil)}
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
    submitted_by = socket.assigns.submitted_by

    if length(entries) == 0 do
      {:noreply, put_flash(socket, :error, "Please select files to upload")}
    else
      # Extract all files (including from ZIP files)
      all_files = extract_uploaded_files(socket)

      # Validate that we have at least one valid file to process
      if length(all_files) == 0 do
        {:noreply,
         put_flash(
           socket,
           :error,
           "No valid X12 files found. ZIP archives must contain .x12, .edi, or .txt files."
         )}
      else
        # Create per-user input/output directories
        {input_dir, _output_dir} = UploadDirs.ensure(submitted_by)

        {:ok, batch} =
          Conversions.create_batch(%{
            name: "Batch Upload - #{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M")}",
            submitted_by: String.trim(submitted_by),
            total_files: length(all_files),
            status: "uploaded"
          })

        Phoenix.PubSub.subscribe(X12Translator.PubSub, "batch:#{batch.id}")

        # Create jobs, store file contents, and write to per-user input directory
        files_to_process =
          Enum.map(all_files, fn {filename, content, file_size} ->
            # Write X12 file to per-user input directory
            input_path = Path.join(input_dir, filename)
            File.write!(input_path, content)

            {:ok, job} =
              Conversions.create_job(%{
                batch_id: batch.id,
                original_filename: filename,
                file_size: file_size,
                status: "uploaded",
                x12_content: content,
                input_path: input_path
              })

            {job.id, content}
          end)
          |> Map.new()

        batches = Conversions.list_batches(limit: 10)

        {:noreply,
         socket
         |> assign(:batches, batches)
         |> assign(:current_batch, Conversions.get_batch!(batch.id))
         |> assign(:uploaded_files, files_to_process)
         |> put_flash(
           :info,
           "Staged #{batch.total_files} files. Click 'Verify' to check X12 structure."
         )}
      end
    end
  end

  @impl true
  def handle_event("verify_batch", _params, socket) do
    batch = socket.assigns.current_batch
    uploaded_files = socket.assigns.uploaded_files

    if batch && map_size(uploaded_files) > 0 do
      Task.start(fn ->
        Conversions.verify_batch_sync(batch.id, uploaded_files)
      end)

      {:noreply,
       socket
       |> assign(:processing_status, :verifying)
       |> put_flash(:info, "Verifying #{batch.total_files} files...")}
    else
      {:noreply, put_flash(socket, :error, "No files to verify")}
    end
  end

  @impl true
  def handle_event("translate_batch", _params, socket) do
    batch = socket.assigns.current_batch
    uploaded_files = socket.assigns.uploaded_files

    if batch && map_size(uploaded_files) > 0 do
      Task.start(fn ->
        Conversions.translate_batch_sync(batch.id, uploaded_files)
      end)

      {:noreply,
       socket
       |> assign(:processing_status, :translating)
       |> put_flash(:info, "Translating verified files...")}
    else
      {:noreply, put_flash(socket, :error, "No verified files to translate")}
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
     # Clear processing status when closing batch
     |> assign(:processing_status, nil)}
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

    if job.status in ["completed", "translated"] && job.json_result do
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
      |> Enum.filter(fn job -> job.status in ["completed", "translated"] && job.json_result end)

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
    batch =
      if socket.assigns.current_batch do
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
     # Mark as completed
     |> assign(:processing_status, :completed)
     |> put_flash(
       :info,
       "Batch completed! #{batch.completed_files} successful, #{batch.failed_files} failed"
     )}
  end

  @impl true
  def handle_info({:remote_import_completed, {:ok, batch}, output_result, output_dir}, socket) do
    batches = Conversions.list_batches(limit: 10)

    # Build message based on output results
    output_msg =
      case output_result do
        %{written: written, failed: 0} ->
          " Output: #{written} JSON files written to #{output_dir}/"

        %{written: written, failed: failed} ->
          " Output: #{written} written, #{failed} failed to #{output_dir}/"

        _ ->
          ""
      end

    {:noreply,
     socket
     |> assign(:batches, batches)
     |> assign(:remote_status, :completed)
     |> assign(:remote_result, batch)
     |> assign(:current_batch, batch)
     |> put_flash(
       :info,
       "Remote import complete! #{batch.completed_files} successful, #{batch.failed_files} failed.#{output_msg}"
     )}
  end

  # Fallback for old message format (without output info)
  @impl true
  def handle_info({:remote_import_completed, {:ok, batch}}, socket) do
    batches = Conversions.list_batches(limit: 10)

    {:noreply,
     socket
     |> assign(:batches, batches)
     |> assign(:remote_status, :completed)
     |> assign(:remote_result, batch)
     |> assign(:current_batch, batch)
     |> put_flash(
       :info,
       "Remote import complete! #{batch.completed_files} successful, #{batch.failed_files} failed"
     )}
  end

  @impl true
  def handle_info({:remote_import_completed, {:error, reason}}, socket) do
    error_message = format_remote_error(reason)

    {:noreply,
     socket
     |> assign(:remote_status, :error)
     |> put_flash(:error, error_message)}
  end

  # === VERIFICATION PUBSUB HANDLERS ===

  @impl true
  def handle_info({:job_verified, _job_id}, socket) do
    batch =
      if socket.assigns.current_batch do
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
  def handle_info({:job_verification_failed, _job_id, _error_message}, socket) do
    batch =
      if socket.assigns.current_batch do
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
  def handle_info({:batch_verified, batch_id, verified_count, failed_count, total_claims}, socket) do
    batch = Conversions.get_batch!(batch_id)
    batches = Conversions.list_batches(limit: 10)

    message =
      if failed_count > 0 do
        "Verification complete! #{verified_count} passed (#{total_claims} claims), #{failed_count} failed"
      else
        "Verification complete! All #{verified_count} files passed (#{total_claims} claims total)"
      end

    {:noreply,
     socket
     |> assign(:batches, batches)
     |> assign(:current_batch, batch)
     |> assign(:processing_status, :verified)
     |> put_flash(:info, message)}
  end

  # === TRANSLATION PUBSUB HANDLERS ===

  @impl true
  def handle_info({:job_translated, _job_id}, socket) do
    batch =
      if socket.assigns.current_batch do
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
  def handle_info({:job_translation_failed, _job_id, _error_message}, socket) do
    batch =
      if socket.assigns.current_batch do
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
  def handle_info(
        {:batch_translated, batch_id, translated_count, failed_count, claims_charged},
        socket
      ) do
    batch = Conversions.get_batch!(batch_id)
    batches = Conversions.list_batches(limit: 10)

    # Write JSON output to per-user output directory
    if batch.submitted_by && String.trim(batch.submitted_by) != "" do
      {_input_dir, output_dir} = UploadDirs.ensure(batch.submitted_by)

      {:ok, result} = X12Translator.OutputWriter.write_batch_output_to_dir(output_dir, batch_id)

      if Map.has_key?(result, :by_job) do
        Enum.each(result.by_job, fn {job_id, paths} ->
          output_path = List.first(paths)
          job = Conversions.get_job!(job_id)
          Conversions.update_job(job, %{output_path: output_path, delivery_status: "ready"})
        end)
      end
    end

    # $0.10 per claim
    cost = claims_charged * 0.10

    message =
      if failed_count > 0 do
        "Translation complete! #{translated_count} succeeded, #{failed_count} failed. Cost: $#{:erlang.float_to_binary(cost, decimals: 2)}"
      else
        "Translation complete! All #{translated_count} files succeeded. Cost: $#{:erlang.float_to_binary(cost, decimals: 2)}"
      end

    {:noreply,
     socket
     |> assign(:batches, batches)
     |> assign(:current_batch, batch)
     |> assign(:processing_status, :translated)
     |> put_flash(:info, message)}
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

    <!-- YOUR NAME (shared across both modes) -->
        <div class="mb-4 mt-4 bg-white shadow rounded-lg p-4">
          <label for="submitted_by" class="block text-sm font-medium text-gray-700 mb-1">
            Your Name
          </label>
          <input
            type="text"
            id="submitted_by"
            name="submitted_by"
            value={@submitted_by}
            placeholder="Enter your name (e.g., John Doe)"
            phx-blur="update_submitted_by"
            class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 text-gray-900 bg-white placeholder-gray-400"
          />
          <p class="mt-1 text-xs text-gray-500">
            Used to organize your files into personal folders
          </p>
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
              <svg
                class="animate-spin h-8 w-8 text-blue-600 flex-shrink-0"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle
                  class="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  stroke-width="4"
                >
                </circle>
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                >
                </path>
              </svg>
              <div class="flex-1">
                <p class="text-sm text-blue-700 font-medium">
                  {@current_batch.completed_files + @current_batch.failed_files} of {@current_batch.total_files} files processed
                </p>
                <% completed = @current_batch.completed_files %>
                <% failed = @current_batch.failed_files %>
                <%= if completed > 0 || failed > 0 do %>
                  <p class="text-xs text-blue-600 mt-1">
                    <span class="text-green-600 font-medium">{completed} successful</span>
                    <%= if failed > 0 do %>
                      · <span class="text-red-600 font-medium">{failed} failed</span>
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
                  {Batch.progress_percentage(@current_batch)}%
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
                <svg
                  class="h-8 w-8 text-green-600"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                <div>
                  <h3 class="text-lg font-bold text-green-900">✅ Processing Complete!</h3>
                  <p class="text-sm text-green-700">
                    {@current_batch.completed_files} successful · {@current_batch.failed_files} failed · {@current_batch.total_files} total
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
              <p class="text-sm text-gray-500">
                Upload individual files or ZIP archives containing multiple X12 files
              </p>
            </div>

            <form phx-submit="process_batch" phx-change="validate_upload" class="space-y-4">
              <div
                class="border-2 border-dashed border-gray-300 rounded-lg p-6"
                phx-drop-target={@uploads.batch_files.ref}
              >
                <.live_file_input upload={@uploads.batch_files} class="hidden" />
                <label
                  for={@uploads.batch_files.ref}
                  class="cursor-pointer flex flex-col items-center"
                >
                  <svg
                    class="w-12 h-12 text-gray-400"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
                    />
                  </svg>
                  <p class="mt-2 text-sm text-gray-600">
                    Click to select or drag and drop files
                  </p>
                  <p class="mt-1 text-xs text-gray-500">
                    X12, EDI, TXT, or ZIP files (up to 50 files, 10MB each)
                  </p>
                  <p class="mt-1 text-xs text-gray-400">
                    ZIP files must contain .x12, .edi, or .txt files
                  </p>
                </label>

                <div
                  :for={entry <- @uploads.batch_files.entries}
                  class="mt-4 p-3 bg-green-50 border border-green-200 rounded-lg"
                >
                  <div class="flex justify-between items-center">
                    <div class="flex-1">
                      <span class="text-base font-semibold text-gray-900">{entry.client_name}</span>
                      <span class="text-sm text-gray-600 ml-3">
                        {format_bytes(entry.client_size)}
                      </span>
                    </div>
                    <button
                      type="button"
                      phx-click="cancel_upload"
                      phx-value-ref={entry.ref}
                      class="ml-4 px-3 py-1 bg-red-100 text-red-700 rounded hover:bg-red-200 transition-colors flex items-center gap-1"
                      title="Remove this file"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M6 18L18 6M6 6l12 12"
                        />
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
                    <p class="text-xs text-green-600 mt-1">Uploading... {entry.progress}%</p>
                  <% end %>
                  
    <!-- Error display -->
                  <%= for err <- upload_errors(@uploads.batch_files, entry) do %>
                    <p class="mt-2 text-sm text-red-600">
                      ⚠️ {error_to_string(err)}
                    </p>
                  <% end %>
                </div>
              </div>

              <%= if length(@uploads.batch_files.entries) > 0 do %>
                <button
                  type="submit"
                  class="w-full px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
                >
                  Stage {length(@uploads.batch_files.entries)} Files for Verification
                </button>
              <% end %>
            </form>
          </div>
          
    <!-- TWO-STAGE PROCESSING PANEL (Verify & Translate) -->
          <%= if @current_batch && @current_batch.status in ["uploaded", "verifying", "verified", "translating", "translated"] do %>
            <div class="mb-8 bg-white shadow rounded-lg p-6 border-2 border-blue-200">
              <div class="mb-4">
                <h2 class="text-xl font-semibold text-gray-900">Processing: {@current_batch.name}</h2>
                <p class="text-sm text-gray-500">
                  {@current_batch.total_files} files staged
                  <%= if @current_batch.submitted_by && @current_batch.submitted_by != "" do %>
                    <span class="text-gray-400 ml-2">by {@current_batch.submitted_by}</span>
                  <% end %>
                </p>
              </div>
              
    <!-- TWO BUTTONS SIDE-BY-SIDE -->
              <div class="flex gap-4 mb-6">
                <!-- STAGE 1: VERIFY BUTTON -->
                <div class="flex-1">
                  <%= if @current_batch.status == "uploaded" do %>
                    <button
                      phx-click="verify_batch"
                      class="w-full px-6 py-4 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-semibold shadow-lg transition-all"
                    >
                      <div class="text-lg">🔍 Stage 1: Verify Files</div>
                      <div class="text-xs mt-1 opacity-90">FREE - Structure Check</div>
                    </button>
                  <% else %>
                    <button
                      disabled
                      class="w-full px-6 py-4 bg-green-100 text-green-800 rounded-lg font-semibold shadow border-2 border-green-300 cursor-not-allowed"
                    >
                      <div class="text-lg">✓ Stage 1: Verified</div>
                      <div class="text-xs mt-1">
                        {@current_batch.verified_files} files, {@current_batch.total_claims} claims
                      </div>
                    </button>
                  <% end %>
                </div>
                
    <!-- STAGE 2: TRANSLATE BUTTON -->
                <div class="flex-1">
                  <%= cond do %>
                    <% @current_batch.status == "verified" -> %>
                      <button
                        phx-click="translate_batch"
                        class="w-full px-6 py-4 bg-green-600 text-white rounded-lg hover:bg-green-700 font-semibold shadow-lg transition-all animate-pulse"
                      >
                        <div class="text-lg">🚀 Stage 2: Translate Files</div>
                        <div class="text-xs mt-1">
                          Cost: ${:erlang.float_to_binary(@current_batch.total_claims * 0.10,
                            decimals: 2
                          )} ({@current_batch.total_claims} claims)
                        </div>
                      </button>
                    <% @current_batch.status == "translated" -> %>
                      <button
                        disabled
                        class="w-full px-6 py-4 bg-green-100 text-green-800 rounded-lg font-semibold shadow border-2 border-green-300 cursor-not-allowed"
                      >
                        <div class="text-lg">✓ Stage 2: Translated</div>
                        <div class="text-xs mt-1">
                          {@current_batch.translated_files} files, {@current_batch.total_claims_charged} claims charged
                        </div>
                      </button>
                    <% true -> %>
                      <button
                        disabled
                        class="w-full px-6 py-4 bg-gray-300 text-gray-500 rounded-lg font-semibold shadow cursor-not-allowed opacity-50"
                      >
                        <div class="text-lg">🔒 Stage 2: Translate Files</div>
                        <div class="text-xs mt-1">
                          <%= if @current_batch.status == "uploaded" do %>
                            Complete Stage 1 first
                          <% else %>
                            {if @current_batch.status == "verifying",
                              do: "Verifying...",
                              else: "Translating..."}
                          <% end %>
                        </div>
                      </button>
                  <% end %>
                </div>
              </div>
              
    <!-- VERIFICATION RESULTS -->
              <%= if @current_batch.status in ["verifying", "verified", "translating", "translated"] do %>
                <div class="mb-4 p-4 bg-blue-50 rounded-lg border border-blue-200">
                  <h3 class="text-sm font-semibold text-blue-900 mb-2">Verification Results:</h3>
                  <div class="grid grid-cols-3 gap-4 text-sm">
                    <div class="bg-white p-3 rounded border border-blue-200">
                      <div class="text-blue-600 font-medium">✓ Verified</div>
                      <div class="text-2xl font-bold text-green-600">
                        {@current_batch.verified_files}
                      </div>
                    </div>
                    <div class="bg-white p-3 rounded border border-blue-200">
                      <div class="text-blue-600 font-medium">✗ Failed</div>
                      <div class="text-2xl font-bold text-red-600">
                        {@current_batch.failed_verification_files}
                      </div>
                    </div>
                    <div class="bg-white p-3 rounded border border-blue-200">
                      <div class="text-blue-600 font-medium">Total Claims</div>
                      <div class="text-2xl font-bold text-blue-900">
                        {@current_batch.total_claims}
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
              
    <!-- TRANSLATION RESULTS -->
              <%= if @current_batch.status in ["translating", "translated"] do %>
                <div class="p-4 bg-green-50 rounded-lg border border-green-200">
                  <h3 class="text-sm font-semibold text-green-900 mb-2">Translation Results:</h3>
                  <div class="grid grid-cols-3 gap-4 text-sm">
                    <div class="bg-white p-3 rounded border border-green-200">
                      <div class="text-green-600 font-medium">✓ Translated</div>
                      <div class="text-2xl font-bold text-green-600">
                        {@current_batch.translated_files}
                      </div>
                    </div>
                    <div class="bg-white p-3 rounded border border-green-200">
                      <div class="text-green-600 font-medium">✗ Failed</div>
                      <div class="text-2xl font-bold text-red-600">
                        {@current_batch.failed_translation_files}
                      </div>
                    </div>
                    <div class="bg-white p-3 rounded border border-green-200">
                      <div class="text-green-600 font-medium">Claims Charged</div>
                      <div class="text-xl font-bold text-green-900">
                        {@current_batch.total_claims_charged}
                        <span class="text-sm font-normal text-green-700">
                          (${:erlang.float_to_binary(@current_batch.total_claims_charged * 0.10,
                            decimals: 2
                          )})
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
              
    <!-- ACTION BUTTONS -->
              <div class="mt-4 flex gap-2">
                <button
                  phx-click="view_batch"
                  phx-value-id={@current_batch.id}
                  class="flex-1 px-4 py-2 bg-gray-100 text-gray-700 rounded-md hover:bg-gray-200"
                >
                  View Details
                </button>
                <%= if @current_batch.status == "translated" && @current_batch.translated_files > 0 do %>
                  <button
                    phx-click="download_batch_zip"
                    phx-value-id={@current_batch.id}
                    class="flex-1 px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700"
                  >
                    Download All JSON Files (ZIP)
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
          
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
                  <svg
                    class="w-4 h-4 group-hover:scale-110 transition-transform"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                    />
                  </svg>
                  Clear All Batches
                </button>
              <% end %>
            </div>

            <%= if length(@batches) == 0 do %>
              <p class="text-gray-500 text-center py-8">
                No batches yet. Upload files to get started!
              </p>
            <% else %>
              <div class="space-y-4">
                <%= for batch <- @batches do %>
                  <div class="border border-gray-200 rounded-lg p-4 hover:shadow-md transition">
                    <div class="flex justify-between items-start">
                      <div class="flex-1">
                        <h3 class="font-medium text-gray-900">
                          {batch.name}
                          <%= if batch.submitted_by && batch.submitted_by != "" do %>
                            <span class="text-xs text-gray-400 font-normal ml-2">by {batch.submitted_by}</span>
                          <% end %>
                        </h3>
                        <p class="text-sm text-gray-500">
                          {Calendar.strftime(batch.inserted_at, "%Y-%m-%d %H:%M")}
                        </p>
                      </div>
                      <div class="flex items-center gap-4">
                        <div class="text-right">
                          <div class="text-sm">
                            <span class="text-green-600 font-medium">{batch.completed_files}</span>
                            / <span class="text-red-600">{batch.failed_files}</span>
                            / <span class="text-gray-600">{batch.total_files}</span>
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
                              <svg
                                class="w-4 h-4"
                                fill="none"
                                stroke="currentColor"
                                viewBox="0 0 24 24"
                              >
                                <path
                                  stroke-linecap="round"
                                  stroke-linejoin="round"
                                  stroke-width="2"
                                  d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                                />
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
              Fetch X12 files from a remote source and process them into your personal folder
            </p>

            <form phx-submit="process_remote_batch" class="space-y-4" autocomplete="off">
              <div>
                <label for="remote-url" class="block text-sm font-medium text-gray-700 mb-2">
                  X12 File Source
                </label>
                <input
                  type="text"
                  id="remote-url"
                  name="url"
                  value={@remote_url}
                  phx-hook="RemoteUrlInput"
                  phx-keyup="url_changed"
                  phx-debounce="300"
                  placeholder="e.g., sftp://hostname/path/to/files or /local/path/"
                  class="w-full px-4 py-2 border border-gray-300 rounded-md focus:ring-purple-500 focus:border-purple-500 text-gray-900 bg-white"
                  autocomplete="off"
                  autocorrect="off"
                  autocapitalize="off"
                  spellcheck="false"
                  required
                />
                <p class="mt-2 text-xs text-gray-500">
                  Supports: SFTP servers • Local directories • ZIP files • HTTP/HTTPS URLs • Databricks
                </p>
              </div>
              
    <!-- SFTP Credentials (shown when URL starts with sftp://) -->
              <%= if @show_sftp_fields do %>
                <div class="p-4 bg-blue-50 border border-blue-200 rounded-lg space-y-3">
                  <h4 class="font-medium text-blue-900 text-sm">🔐 SFTP Credentials</h4>
                  <div class="grid grid-cols-3 gap-3">
                    <div>
                      <label class="block text-xs font-medium text-gray-700 mb-1">Username</label>
                      <input
                        type="text"
                        name="sftp_username"
                        value={@sftp_username}
                        phx-keyup="update_sftp_field"
                        phx-value-field="username"
                        placeholder="username"
                        class="w-full px-3 py-2 border border-gray-300 rounded-md text-sm text-gray-900 bg-white"
                        autocomplete="off"
                      />
                    </div>
                    <div>
                      <label class="block text-xs font-medium text-gray-700 mb-1">Password</label>
                      <input
                        type="password"
                        name="sftp_password"
                        value={@sftp_password}
                        phx-keyup="update_sftp_field"
                        phx-value-field="password"
                        placeholder="••••••••"
                        class="w-full px-3 py-2 border border-gray-300 rounded-md text-sm text-gray-900 bg-white"
                        autocomplete="off"
                      />
                    </div>
                    <div>
                      <label class="block text-xs font-medium text-gray-700 mb-1">Port</label>
                      <input
                        type="number"
                        name="sftp_port"
                        value={@sftp_port}
                        phx-keyup="update_sftp_field"
                        phx-value-field="port"
                        placeholder="22"
                        class="w-full px-3 py-2 border border-gray-300 rounded-md text-sm text-gray-900 bg-white"
                        autocomplete="off"
                      />
                    </div>
                  </div>
                  <p class="text-xs text-blue-700">
                    Enter your SFTP server credentials. The hostname is taken from the URL above.
                  </p>
                </div>
              <% end %>

              <button
                type="submit"
                disabled={@remote_status == :processing}
                class="w-full px-4 py-2 bg-purple-600 text-white rounded-md hover:bg-purple-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {if @remote_status == :processing,
                  do: "⏳ Downloading and Processing...",
                  else: "🚀 Fetch & Process"}
              </button>
            </form>
            
    <!-- Remote Processing Status -->
            <%= if @remote_status == :processing do %>
              <div class="mt-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
                <div class="flex items-center gap-3">
                  <svg
                    class="animate-spin h-5 w-5 text-blue-600"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <circle
                      class="opacity-25"
                      cx="12"
                      cy="12"
                      r="10"
                      stroke="currentColor"
                      stroke-width="4"
                    >
                    </circle>
                    <path
                      class="opacity-75"
                      fill="currentColor"
                      d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                    >
                    </path>
                  </svg>
                  <div>
                    <p class="font-semibold text-blue-900">Downloading and processing...</p>
                    <p class="text-sm text-blue-700">
                      Files are staged locally before translation. This may take a moment depending on file size.
                    </p>
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
                    <span class="ml-2 font-semibold">{@remote_result.name}</span>
                  </div>
                  <div>
                    <span class="text-gray-600">Total Files:</span>
                    <span class="ml-2 font-semibold">{@remote_result.total_files}</span>
                  </div>
                  <div>
                    <span class="text-gray-600">Successful:</span>
                    <span class="ml-2 font-semibold text-green-600">
                      {@remote_result.completed_files}
                    </span>
                  </div>
                  <div>
                    <span class="text-gray-600">Failed:</span>
                    <span class="ml-2 font-semibold text-red-600">{@remote_result.failed_files}</span>
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
              <h4 class="font-semibold text-purple-900 mb-2">ℹ️ Supported Sources:</h4>
              <ul class="space-y-1 text-purple-800 text-xs">
                <li>
                  <strong>Local Directory:</strong>
                  /path/to/x12_files/ - reads all .x12, .edi, .txt files
                </li>
                <li>
                  <strong>Local ZIP File:</strong>
                  /path/to/batch.zip - extracts and processes X12 files
                </li>
                <li><strong>Single X12 File:</strong> /path/to/claim.x12 - processes one file</li>
                <li>
                  <strong>HTTP/HTTPS URL:</strong>
                  https://example.com/batch.zip - downloads and extracts
                </li>
                <li>
                  <strong>SFTP Server:</strong>
                  sftp://user@host/path/to/files - enter credentials above
                </li>
                <li>
                  <strong>Databricks:</strong> /mnt/data/x12/batch.zip - requires Databricks config
                </li>
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
                    <svg
                      class="w-4 h-4 group-hover:scale-110 transition-transform"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                      />
                    </svg>
                    Clear All Batches
                  </button>
                <% end %>
              </div>
              <%= if length(@batches) == 0 do %>
                <p class="text-gray-500 text-center py-8">
                  No remote imports yet. Enter a URL to get started!
                </p>
              <% else %>
                <div class="space-y-4">
                  <%= for batch <- Enum.filter(@batches, fn b -> String.starts_with?(b.name, "Remote Import") end) do %>
                    <div class="border border-gray-200 rounded-lg p-4 hover:shadow-md transition">
                      <div class="flex justify-between items-start">
                        <div class="flex-1">
                          <h3 class="font-medium text-gray-900">{batch.name}</h3>
                          <p class="text-sm text-gray-500">
                            {Calendar.strftime(batch.inserted_at, "%Y-%m-%d %H:%M")}
                          </p>
                        </div>
                        <div class="flex items-center gap-4">
                          <div class="text-right">
                            <div class="text-sm">
                              <span class="text-green-600 font-medium">{batch.completed_files}</span>
                              / <span class="text-red-600">{batch.failed_files}</span>
                              / <span class="text-gray-600">{batch.total_files}</span>
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
                                <svg
                                  class="w-4 h-4"
                                  fill="none"
                                  stroke="currentColor"
                                  viewBox="0 0 24 24"
                                >
                                  <path
                                    stroke-linecap="round"
                                    stroke-linejoin="round"
                                    stroke-width="2"
                                    d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                                  />
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
          <div
            class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50"
            phx-click="close_batch"
          >
            <div
              class="bg-white rounded-lg max-w-4xl w-full max-h-[90vh] overflow-hidden flex flex-col"
              phx-click="stop_propagation"
            >
              <div class="p-6 border-b flex justify-between items-center">
                <div>
                  <h2 class="text-2xl font-bold text-gray-900">{@current_batch.name}</h2>
                  <p class="text-sm text-gray-500 flex items-center gap-2">
                    {@current_batch.completed_files + @current_batch.failed_files} / {@current_batch.total_files} processed
                    <%= if @current_batch.submitted_by && @current_batch.submitted_by != "" do %>
                      <span class="text-gray-400">by {@current_batch.submitted_by}</span>
                    <% end %>
                    <span class="ml-2 text-xs text-gray-400">
                      Last update: {Calendar.strftime(@current_batch.updated_at, "%H:%M:%S")}
                    </span>
                  </p>
                </div>
                <button
                  phx-click="close_batch"
                  class="text-gray-400 hover:text-gray-600"
                >
                  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M6 18L18 6M6 6l12 12"
                    />
                  </svg>
                </button>
              </div>
              
    <!-- TWO-STAGE BUTTONS IN MODAL -->
              <%= if @current_batch.status in ["uploaded", "verifying", "verified", "translating", "translated"] do %>
                <div class="p-6 border-b bg-gray-50">
                  <div class="flex gap-4 mb-4">
                    <!-- STAGE 1: VERIFY BUTTON -->
                    <div class="flex-1">
                      <%= if @current_batch.status == "uploaded" do %>
                        <button
                          phx-click="verify_batch"
                          class="w-full px-6 py-4 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-semibold shadow-lg transition-all"
                        >
                          <div class="text-lg">🔍 Stage 1: Verify Files</div>
                          <div class="text-xs mt-1 opacity-90">FREE - Structure Check</div>
                        </button>
                      <% else %>
                        <button
                          disabled
                          class="w-full px-6 py-4 bg-green-100 text-green-800 rounded-lg font-semibold shadow border-2 border-green-300 cursor-not-allowed"
                        >
                          <div class="text-lg">✓ Stage 1: Verified</div>
                          <div class="text-xs mt-1">
                            {@current_batch.verified_files} files, {@current_batch.total_claims} claims
                          </div>
                        </button>
                      <% end %>
                    </div>
                    
    <!-- STAGE 2: TRANSLATE BUTTON -->
                    <div class="flex-1">
                      <%= cond do %>
                        <% @current_batch.status == "verified" -> %>
                          <button
                            phx-click="translate_batch"
                            class="w-full px-6 py-4 bg-green-600 text-white rounded-lg hover:bg-green-700 font-semibold shadow-lg transition-all animate-pulse"
                          >
                            <div class="text-lg">🚀 Stage 2: Translate Files</div>
                            <div class="text-xs mt-1">
                              Cost: ${:erlang.float_to_binary(@current_batch.total_claims * 0.10,
                                decimals: 2
                              )} ({@current_batch.total_claims} claims)
                            </div>
                          </button>
                        <% @current_batch.status == "translated" -> %>
                          <button
                            disabled
                            class="w-full px-6 py-4 bg-green-100 text-green-800 rounded-lg font-semibold shadow border-2 border-green-300 cursor-not-allowed"
                          >
                            <div class="text-lg">✓ Stage 2: Translated</div>
                            <div class="text-xs mt-1">
                              {@current_batch.translated_files} files, {@current_batch.total_claims_charged} claims charged
                            </div>
                          </button>
                        <% true -> %>
                          <button
                            disabled
                            class="w-full px-6 py-4 bg-gray-300 text-gray-500 rounded-lg font-semibold shadow cursor-not-allowed opacity-50"
                          >
                            <div class="text-lg">🔒 Stage 2: Translate Files</div>
                            <div class="text-xs mt-1">
                              <%= if @current_batch.status == "uploaded" do %>
                                Complete Stage 1 first
                              <% else %>
                                {if @current_batch.status == "verifying",
                                  do: "Verifying...",
                                  else: "Translating..."}
                              <% end %>
                            </div>
                          </button>
                      <% end %>
                    </div>
                  </div>
                  
    <!-- VERIFICATION SUMMARY -->
                  <%= if @current_batch.status in ["verified", "translating", "translated"] do %>
                    <div class="flex gap-3 text-sm">
                      <div class="flex-1 bg-white p-3 rounded border border-green-200">
                        <div class="text-green-600 font-medium text-xs">✓ Verified</div>
                        <div class="text-xl font-bold text-green-700">
                          {@current_batch.verified_files}
                        </div>
                      </div>
                      <div class="flex-1 bg-white p-3 rounded border border-gray-200">
                        <div class="text-gray-600 font-medium text-xs">Total Claims</div>
                        <div class="text-xl font-bold text-blue-600">
                          {@current_batch.total_claims}
                        </div>
                      </div>
                      <%= if @current_batch.status in ["translating", "translated"] do %>
                        <div class="flex-1 bg-white p-3 rounded border border-blue-200">
                          <div class="text-blue-600 font-medium text-xs">🚀 Translated</div>
                          <div class="text-xl font-bold text-blue-700">
                            {@current_batch.translated_files}
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <div class="flex-1 overflow-y-auto p-6">
                <div class="space-y-3">
                  <%= for job <- @current_batch.jobs do %>
                    <div class="border border-gray-200 rounded-lg p-4">
                      <div class="flex justify-between items-center">
                        <div class="flex-1">
                          <h4 class="font-medium text-gray-900">{job.original_filename}</h4>
                          <p class="text-sm text-gray-500">{format_bytes(job.file_size)}</p>
                        </div>
                        <div class="flex items-center gap-3">
                          <span class={"px-3 py-1 rounded-full text-sm " <> status_class(job.status)}>
                            {String.upcase(job.status)}
                          </span>
                          <%= if job.status == "verified" do %>
                            <span class="text-xs text-green-700">
                              {job.claim_count} claim(s) found
                            </span>
                          <% end %>
                          <%= if job.status in ["translated", "completed"] do %>
                            <button
                              phx-click={
                                if @viewing_job_id == to_string(job.id),
                                  do: "hide_job_json",
                                  else: "view_job_json"
                              }
                              phx-value-id={job.id}
                              class="px-3 py-1 bg-blue-100 text-blue-700 rounded hover:bg-blue-200"
                            >
                              {if @viewing_job_id == to_string(job.id),
                                do: "Hide Comparison",
                                else: "View Side-by-Side"}
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
                      <%= if job.verification_error do %>
                        <div class="mt-2 p-2 bg-yellow-50 border border-yellow-200 text-yellow-900 text-sm rounded">
                          <div class="font-semibold">Verification Errors:</div>
                          {job.verification_error}
                        </div>
                      <% end %>
                      <%= if job.error_message do %>
                        <div class="mt-2 p-2 bg-red-50 text-red-700 text-sm rounded">
                          <div class="font-semibold">Translation Error:</div>
                          {job.error_message}
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
                        <div
                          class="grid grid-cols-2 gap-4"
                          phx-hook="SyncScroll"
                          id={"sync-scroll-#{job.id}"}
                        >
                          <!-- X12 Content (Left) -->
                          <div class="flex flex-col">
                            <h6 class="text-xs font-semibold text-gray-600 mb-2 bg-gray-200 p-2 rounded">
                              Original X12 File:
                            </h6>
                            <pre
                              data-sync-scroll
                              class="bg-white p-4 rounded border border-gray-200 overflow-x-auto text-black text-sm font-mono max-h-[600px] overflow-y-auto flex-1"
                              style="color: black !important;"
                            ><%= job.x12_content || "X12 content not available" %></pre>
                          </div>
                          <!-- JSON Output (Right) -->
                          <div class="flex flex-col">
                            <h6 class="text-xs font-semibold text-gray-600 mb-2 bg-gray-200 p-2 rounded">
                              Converted JSON:
                            </h6>
                            <pre
                              data-sync-scroll
                              class="bg-white p-4 rounded border border-gray-200 overflow-x-auto text-black text-sm font-mono max-h-[600px] overflow-y-auto flex-1"
                              style="color: black !important;"
                            ><%= job.json_result %></pre>
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
    temp_dir = Path.join(System.tmp_dir!(), "x12_zip_#{:rand.uniform(999_999)}")
    File.mkdir_p!(temp_dir)

    try do
      # Extract ZIP file
      case :zip.unzip(String.to_charlist(zip_path), cwd: String.to_charlist(temp_dir)) do
        {:ok, extracted_files} ->
          # Read all extracted files
          x12_files =
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

          # Log info about what was found
          total_files = length(Enum.filter(extracted_files, &(!File.dir?(to_string(&1)))))
          x12_count = length(x12_files)

          if x12_count == 0 && total_files > 0 do
            require Logger

            Logger.warning(
              "ZIP archive contains #{total_files} files but no valid X12 files (.x12, .edi, .txt)"
            )
          end

          x12_files

        {:error, reason} ->
          # If ZIP extraction fails, return empty list
          require Logger
          Logger.error("Failed to extract ZIP: #{inspect(reason)}")
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
    # Limit length
    |> String.slice(0..50)
  end

  defp status_class("uploaded"), do: "bg-gray-100 text-gray-800"
  defp status_class("verifying"), do: "bg-blue-100 text-blue-800"
  defp status_class("verified"), do: "bg-green-100 text-green-800"
  defp status_class("failed_verification"), do: "bg-red-100 text-red-800"
  defp status_class("translating"), do: "bg-purple-100 text-purple-800"
  defp status_class("translated"), do: "bg-green-100 text-green-800"
  defp status_class("failed_translation"), do: "bg-red-100 text-red-800"
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

  defp copy_files_to_input(files, source, input_dir) do
    uri = URI.parse(source)
    remote_host = uri.host
    remote_base = uri.path || "/"

    Enum.reduce(files, {[], %{}}, fn temp_path, {acc_files, acc_metadata} ->
      filename = Path.basename(temp_path)
      dest_path = unique_dest_path(input_dir, filename)

      case File.cp(temp_path, dest_path) do
        :ok ->
          remote_path = build_remote_path(remote_base, filename, length(files))

          metadata =
            acc_metadata
            |> Map.put(dest_path, %{
              remote_host: remote_host,
              remote_path: remote_path,
              remote_source_url: source
            })

          {[dest_path | acc_files], metadata}

        {:error, reason} ->
          Logger.error("Failed to copy #{temp_path}: #{inspect(reason)}")
          {acc_files, acc_metadata}
      end
    end)
    |> then(fn {files_copied, metadata} -> {Enum.reverse(files_copied), metadata} end)
  end

  defp build_remote_path(base_path, filename, file_count) do
    cond do
      file_count <= 1 ->
        base_path

      String.ends_with?(base_path, "/") ->
        Path.join(base_path, filename)

      true ->
        Path.join(base_path, filename)
    end
  end

  defp unique_dest_path(input_dir, filename) do
    base = Path.rootname(filename)
    ext = Path.extname(filename)

    candidate = Path.join(input_dir, filename)

    if File.exists?(candidate) do
      find_unique_path(input_dir, base, ext, 1)
    else
      candidate
    end
  end

  defp find_unique_path(input_dir, base, ext, index) do
    candidate = Path.join(input_dir, "#{base}_#{index}#{ext}")

    if File.exists?(candidate) do
      find_unique_path(input_dir, base, ext, index + 1)
    else
      candidate
    end
  end

  defp format_remote_error(:invalid_url),
    do:
      "Invalid source. Please enter a valid HTTP/HTTPS URL, local file path, or Databricks path."

  defp format_remote_error(:invalid_path),
    do: "File not found. Please check the file path and try again."

  defp format_remote_error(:download_failed),
    do: "Failed to download file. Please check the URL and try again."

  defp format_remote_error({:http_error, 404}), do: "File not found (404). Please verify the URL."
  defp format_remote_error({:http_error, 500}), do: "Server error (500). Please try again later."
  defp format_remote_error({:http_error, status}), do: "HTTP error (#{status}). Please try again."

  defp format_remote_error(:timeout),
    do: "Download timed out. The file may be too large or the server is slow."

  defp format_remote_error(:invalid_zip),
    do: "Invalid ZIP file. Please ensure the file is a valid ZIP archive."

  defp format_remote_error(:no_x12_files),
    do: "No X12 files found in ZIP. Expected .x12, .edi, or .txt files."

  defp format_remote_error(:file_too_large), do: "File exceeds maximum size of 100MB."

  defp format_remote_error(:databricks_not_configured),
    do:
      "Databricks is not configured. Please set DATABRICKS_HOST and DATABRICKS_TOKEN environment variables."

  defp format_remote_error({:databricks_error, status}),
    do: "Databricks API error (#{status}). Please check your credentials and path."

  defp format_remote_error(:invalid_databricks_response),
    do: "Invalid response from Databricks API. Please check the file path."

  defp format_remote_error(:sftp_not_configured),
    do:
      "SFTP is not configured. Please set SFTP_HOST, SFTP_USERNAME, and SFTP_PASSWORD environment variables."

  defp format_remote_error(:sftp_connection_failed),
    do: "Failed to connect to SFTP server. Please check the hostname, port, and credentials."

  defp format_remote_error(:sftp_channel_failed),
    do: "Failed to start SFTP session. The server may not support SFTP."

  defp format_remote_error(:sftp_list_failed),
    do: "Failed to list remote directory. Please check the path exists and you have permission."

  defp format_remote_error(_), do: "An error occurred while processing the file."

  # Convert upload errors to human-readable strings
  defp error_to_string(:too_large), do: "File is too large (max 10MB)"

  defp error_to_string(:not_accepted),
    do: "File type not accepted (use .x12, .edi, .txt, or .zip)"

  defp error_to_string(:too_many_files), do: "Too many files (max 50)"
  defp error_to_string(:external_client_failure), do: "Upload failed - please try again"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"
end
