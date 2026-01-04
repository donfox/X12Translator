defmodule X12BridgeWeb.BatchLiveEnhanced do
  @moduledoc """
  Enhanced Batch Processing page that supports:
  1. Web upload (database-backed)
  2. Hot folder processing (file-based)
  3. Real-time progress updates
  """
  use X12BridgeWeb, :live_view

  import X12BridgeWeb.Layouts, only: [app_layout: 1]

  alias X12Bridge.Conversions
  alias X12Bridge.Conversions.Batch
  alias X12Bridge.BatchProcessor

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(X12Bridge.PubSub, "batches")
      Phoenix.PubSub.subscribe(X12Bridge.PubSub, "batch_processor")
    end

    batches = Conversions.list_batches(limit: 10)

    {:ok,
     socket
     |> assign(:batches, batches)
     |> assign(:current_batch, nil)
     |> assign(:show_upload, false)
     |> assign(:processing_mode, :upload)  # :upload or :hot_folder
     |> assign(:hot_folder_status, nil)
     |> assign(:hot_folder_result, nil)
     |> allow_upload(:batch_files,
         accept: [".x12", ".edi", ".txt"],
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

  # === DATABASE UPLOAD EVENTS (Original) ===

  @impl true
  def handle_event("toggle_upload", _params, socket) do
    {:noreply, assign(socket, :show_upload, !socket.assigns.show_upload)}
  end

  @impl true
  def handle_event("process_batch", _params, socket) do
    entries = socket.assigns.uploads.batch_files.entries

    if length(entries) == 0 do
      {:noreply, put_flash(socket, :error, "Please select files to upload")}
    else
      {:ok, batch} = Conversions.create_batch(%{
        name: "Batch Upload - #{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M")}",
        total_files: length(entries)
      })

      Phoenix.PubSub.subscribe(X12Bridge.PubSub, "batch:#{batch.id}")

      files_to_process =
        consume_uploaded_entries(socket, :batch_files, fn %{path: path}, entry ->
          {:ok, content} = File.read(path)

          {:ok, job} = Conversions.create_job(%{
            batch_id: batch.id,
            original_filename: entry.client_name,
            file_size: entry.client_size,
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
       |> assign(:show_upload, false)
       |> put_flash(:info, "Processing #{batch.total_files} files...")}
    end
  end

  @impl true
  def handle_event("load_test_batch", %{"batch_name" => batch_name}, socket) do
    case X12Bridge.TestSupport.BatchLoader.load_batch(batch_name) do
      {:ok, batch_data} ->
        {:ok, batch} = Conversions.create_batch(%{
          name: "Test: #{batch_data.description}",
          total_files: batch_data.total_files
        })

        Phoenix.PubSub.subscribe(X12Bridge.PubSub, "batch:#{batch.id}")

        files_to_process =
          Enum.map(batch_data.files, fn file ->
            {:ok, job} = Conversions.create_job(%{
              batch_id: batch.id,
              original_filename: file.filename,
              file_size: byte_size(file.content),
              status: "pending"
            })

            {job.id, file.content}
          end)

        Task.start(fn ->
          Conversions.process_batch_sync(batch.id, files_to_process)
        end)

        batches = Conversions.list_batches(limit: 10)

        {:noreply,
         socket
         |> assign(:batches, batches)
         |> assign(:current_batch, batch)
         |> put_flash(:info, "Processing test batch: #{batch_name}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to load batch: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("view_batch", %{"id" => id}, socket) do
    batch = Conversions.get_batch!(id)
    {:noreply, assign(socket, :current_batch, batch)}
  end

  @impl true
  def handle_event("close_batch", _params, socket) do
    {:noreply, assign(socket, :current_batch, nil)}
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

  # === RENDER ===

  @impl true
  def render(assigns) do
    ~H"""
    <.app_layout flash={@flash}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-white">Batch Processing</h1>
          <p class="mt-2 text-gray-300">
            Process multiple X12 files using web upload or hot folder
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
                📤 Web Upload (Database)
              </button>
              <button
                phx-click="switch_mode"
                phx-value-mode="hot_folder"
                class={"px-4 py-2 rounded-md transition " <> if @processing_mode == :hot_folder, do: "bg-green-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600"}
              >
                📁 Hot Folder (File System)
              </button>
            </div>
          </div>
        </div>

        <!-- WEB UPLOAD MODE -->
        <%= if @processing_mode == :upload do %>
          <div class="mb-8 bg-white shadow rounded-lg p-6">
            <div class="flex justify-between items-center mb-4">
              <div>
                <h2 class="text-xl font-semibold text-gray-900">Upload Files</h2>
                <p class="text-sm text-gray-500">Files are stored in database and processed</p>
              </div>
              <button
                phx-click="toggle_upload"
                class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
              >
                <%= if @show_upload, do: "Hide Upload", else: "Upload Files" %>
              </button>
            </div>

            <%= if @show_upload do %>
              <form phx-submit="process_batch" class="space-y-4">
                <div class="border-2 border-dashed border-gray-300 rounded-lg p-6">
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
                      X12, EDI, or TXT files (up to 50 files, 10MB each)
                    </p>
                  </label>

                  <div :for={entry <- @uploads.batch_files.entries} class="mt-4 p-2 bg-gray-50 rounded flex justify-between items-center">
                    <span class="text-sm"><%= entry.client_name %></span>
                    <span class="text-xs text-gray-500"><%= format_bytes(entry.client_size) %></span>
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
            <% end %>

            <div class="mt-6 pt-6 border-t border-gray-200">
              <h3 class="text-sm font-medium text-gray-700 mb-2">Load Test Batch (Database Mode):</h3>
              <div class="flex gap-2">
                <button
                  phx-click="load_test_batch"
                  phx-value-batch_name="batch_quick"
                  class="px-3 py-1 text-sm bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
                >
                  Quick (5 files)
                </button>
                <button
                  phx-click="load_test_batch"
                  phx-value-batch_name="batch_realistic"
                  class="px-3 py-1 text-sm bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
                >
                  Realistic (50 files)
                </button>
              </div>
            </div>
          </div>

          <!-- Database Batches List -->
          <div class="bg-white shadow rounded-lg p-6">
            <h2 class="text-xl font-semibold text-gray-900 mb-4">Recent Batches (Database)</h2>

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
                        <button
                          phx-click="view_batch"
                          phx-value-id={batch.id}
                          class="px-3 py-1 bg-blue-100 text-blue-700 rounded hover:bg-blue-200"
                        >
                          View
                        </button>
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

        <!-- HOT FOLDER MODE -->
        <%= if @processing_mode == :hot_folder do %>
          <div class="mb-8 bg-white shadow rounded-lg p-6">
            <h2 class="text-xl font-semibold text-gray-900 mb-4">Hot Folder Processing</h2>
            <p class="text-sm text-gray-600 mb-6">
              Files are processed from <code class="bg-gray-100 px-2 py-1 rounded">priv/batch_processing/input/</code>
            </p>

            <div class="space-y-4">
              <button
                phx-click="process_hot_folder"
                disabled={@hot_folder_status == :processing}
                class="w-full px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <%= if @hot_folder_status == :processing, do: "Processing...", else: "🚀 Process Input Directory" %>
              </button>

              <button
                phx-click="view_hot_folder_results"
                class="w-full px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
              >
                📂 Open Output Directory
              </button>
            </div>

            <div class="mt-6 pt-6 border-t border-gray-200">
              <h3 class="text-sm font-medium text-gray-700 mb-2">Process Test Batch (Hot Folder Mode):</h3>
              <p class="text-xs text-gray-500 mb-3">These use the concurrent BatchProcessor module</p>
              <div class="grid grid-cols-3 gap-2">
                <button
                  phx-click="process_test_batch_hot_folder"
                  phx-value-batch_name="batch_quick"
                  class="px-3 py-2 text-sm bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
                >
                  Quick (5 files)
                </button>
                <button
                  phx-click="process_test_batch_hot_folder"
                  phx-value-batch_name="batch_realistic"
                  class="px-3 py-2 text-sm bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
                >
                  Realistic (50 files)
                </button>
                <button
                  phx-click="process_test_batch_hot_folder"
                  phx-value-batch_name="batch_performance"
                  class="px-3 py-2 text-sm bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
                >
                  Performance (500 files)
                </button>
              </div>
            </div>

            <!-- Hot Folder Results -->
            <%= if @hot_folder_result do %>
              <div class="mt-6 p-4 bg-green-50 border border-green-200 rounded-lg">
                <div class="flex justify-between items-start mb-4">
                  <h3 class="font-semibold text-green-900">✓ Processing Complete</h3>
                  <button
                    phx-click="clear_hot_folder_result"
                    class="text-green-700 hover:text-green-900"
                  >
                    ✕
                  </button>
                </div>

                <div class="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <span class="text-gray-600">Batch ID:</span>
                    <span class="ml-2 font-mono text-xs"><%= @hot_folder_result.batch_id %></span>
                  </div>
                  <div>
                    <span class="text-gray-600">Total Files:</span>
                    <span class="ml-2 font-semibold"><%= @hot_folder_result.total_files %></span>
                  </div>
                  <div>
                    <span class="text-gray-600">Successful:</span>
                    <span class="ml-2 font-semibold text-green-600"><%= @hot_folder_result.successful_files %></span>
                  </div>
                  <div>
                    <span class="text-gray-600">Failed:</span>
                    <span class="ml-2 font-semibold text-red-600"><%= @hot_folder_result.failed_files %></span>
                  </div>
                  <div>
                    <span class="text-gray-600">Processing Time:</span>
                    <span class="ml-2"><%= @hot_folder_result.processing_time_ms %>ms</span>
                  </div>
                  <div>
                    <span class="text-gray-600">Throughput:</span>
                    <span class="ml-2"><%= round(@hot_folder_result.total_files / (@hot_folder_result.processing_time_ms / 1000)) %> files/sec</span>
                  </div>
                </div>

                <div class="mt-4 pt-4 border-t border-green-200">
                  <p class="text-sm text-gray-700 mb-2">
                    <strong>Output:</strong> <code class="bg-white px-2 py-1 rounded text-xs"><%= Path.basename(@hot_folder_result.output_directory) %></code>
                  </p>
                  <p class="text-sm text-gray-700">
                    <strong>Manifest:</strong> <code class="bg-white px-2 py-1 rounded text-xs"><%= Path.basename(@hot_folder_result.manifest_path) %></code>
                  </p>
                </div>
              </div>
            <% end %>

            <!-- Directory Info -->
            <div class="mt-6 p-4 bg-blue-50 border border-blue-200 rounded-lg text-sm">
              <h4 class="font-semibold text-blue-900 mb-2">📁 Directory Structure:</h4>
              <ul class="space-y-1 text-blue-800 font-mono text-xs">
                <li>→ Input: <code>priv/batch_processing/input/</code></li>
                <li>→ Output: <code>priv/batch_processing/output/</code></li>
                <li>→ Failed: <code>priv/batch_processing/failed/</code></li>
              </ul>
            </div>
          </div>
        <% end %>

        <!-- Batch Detail Modal (for database batches) -->
        <%= if @current_batch do %>
          <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
            <div class="bg-white rounded-lg max-w-4xl w-full max-h-[90vh] overflow-hidden flex flex-col">
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

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp status_class("completed"), do: "bg-green-100 text-green-800"
  defp status_class("failed"), do: "bg-red-100 text-red-800"
  defp status_class("processing"), do: "bg-blue-100 text-blue-800"
  defp status_class("pending"), do: "bg-gray-100 text-gray-800"
  defp status_class(_), do: "bg-gray-100 text-gray-800"
end
