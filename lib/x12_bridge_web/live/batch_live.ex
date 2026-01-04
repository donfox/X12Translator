defmodule X12BridgeWeb.BatchLive do
  use X12BridgeWeb, :live_view

  import X12BridgeWeb.Layouts, only: [app_layout: 1]

  alias X12Bridge.Conversions
  alias X12Bridge.Conversions.Batch

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to batch updates for this user
      # In production, you'd filter by user_id
      Phoenix.PubSub.subscribe(X12Bridge.PubSub, "batches")
    end

    batches = Conversions.list_batches(limit: 10)

    {:ok,
     socket
     |> assign(:batches, batches)
     |> assign(:current_batch, nil)
     |> assign(:show_upload, false)
     |> allow_upload(:batch_files,
         accept: [".x12", ".edi", ".txt"],
         max_entries: 50,
         max_file_size: 10_000_000)}
  end

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
      # Create batch record
      {:ok, batch} = Conversions.create_batch(%{
        name: "Batch Upload - #{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M")}",
        total_files: length(entries)
      })

      # Subscribe to this batch's updates
      Phoenix.PubSub.subscribe(X12Bridge.PubSub, "batch:#{batch.id}")

      # Process uploaded files
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

      # Process batch in background
      Task.start(fn ->
        Conversions.process_batch_sync(batch.id, files_to_process)
      end)

      # Reload batches list
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
        # Create batch from test data
        {:ok, batch} = Conversions.create_batch(%{
          name: "Test: #{batch_data.description}",
          total_files: batch_data.total_files
        })

        Phoenix.PubSub.subscribe(X12Bridge.PubSub, "batch:#{batch.id}")

        # Create jobs and process
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

        # Process batch
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

  # PubSub handlers
  @impl true
  def handle_info({:job_completed, _job_id, _status}, socket) do
    # Reload current batch if viewing one
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
  def render(assigns) do
    ~H"""
    <.app_layout flash={@flash}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Header -->
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-white">Batch Processing</h1>
        <p class="mt-2 text-gray-300">
          Upload multiple X12 files for batch conversion
        </p>
      </div>

      <!-- Upload Section -->
      <div class="mb-8 bg-white shadow rounded-lg p-6">
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-xl font-semibold text-gray-900">Upload Files</h2>
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

              <!-- Show selected files -->
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

        <!-- Test Batches -->
        <div class="mt-6 pt-6 border-t border-gray-200">
          <h3 class="text-sm font-medium text-gray-700 mb-2">Load Test Batch:</h3>
          <div class="flex gap-2">
            <button
              phx-click="load_test_batch"
              phx-value-batch_name="batch_quick"
              class="px-3 py-1 text-sm bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
            >
              Quick (5 files)
            </button>
          </div>
        </div>
      </div>

      <!-- Batches List -->
      <div class="bg-white shadow rounded-lg p-6">
        <h2 class="text-xl font-semibold text-gray-900 mb-4">Recent Batches</h2>

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

                <!-- Progress bar -->
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

      <!-- Batch Detail Modal -->
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
