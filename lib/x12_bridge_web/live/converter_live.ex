defmodule X12BridgeWeb.ConverterLive do
  use X12BridgeWeb, :live_view

  import X12BridgeWeb.Layouts, only: [app_layout: 1]

  alias X12Bridge.X12.{Converter, Validator}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:x12_content, "")
     |> assign(:json_result, nil)
     |> assign(:validation_result, nil)
     |> assign(:processing, false)
     |> assign(:error, nil)
     |> assign(:form_key, System.system_time(:millisecond))
     |> allow_upload(:x12_file, accept: [".x12", ".edi", ".txt"], max_entries: 1)}
  end

  @impl true
  def handle_event("load_sample", %{"type" => type}, socket) do
    sample_path =
      case type do
        "837p" -> "priv/test_data/single/sample_837p.x12"
        "837i" -> "priv/test_data/single/sample_837i.x12"
        "837d" -> "priv/test_data/single/sample_837d.x12"
        _ -> nil
      end

    if sample_path && File.exists?(sample_path) do
      case File.read(sample_path) do
        {:ok, content} ->
          {:noreply,
           socket
           |> assign(:x12_content, content)
           |> assign(:json_result, nil)
           |> assign(:validation_result, nil)
           |> assign(:form_key, System.system_time(:millisecond))
           |> put_flash(:info, "Sample #{type} loaded successfully")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to load sample file: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Sample file not found at #{sample_path}")}
    end
  end

  @impl true
  def handle_event("validate", _params, socket) do
    content = socket.assigns.x12_content

    if String.trim(content) == "" do
      {:noreply,
       socket
       |> assign(:validation_result, nil)
       |> assign(:json_result, nil)}
    else
      validation_result = Validator.validate_content(content)

      {:noreply,
       socket
       |> assign(:validation_result, validation_result)
       |> assign(:json_result, nil)}
    end
  end

  @impl true
  def handle_event("convert", _params, socket) do
    content = socket.assigns.x12_content

    if String.trim(content) == "" do
      {:noreply, put_flash(socket, :error, "Please provide X12 content first")}
    else
      # First validate
      validation_result = Validator.validate_content(content)

      # Then convert
      socket =
        socket
        |> assign(:processing, true)
        |> assign(:validation_result, validation_result)

      case Converter.convert_content(content) do
        {:ok, json} ->
          {:noreply,
           socket
           |> assign(:json_result, json)
           |> assign(:processing, false)
           |> assign(:error, nil)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:processing, false)
           |> assign(:error, "Conversion failed: #{reason}")
           |> put_flash(:error, "Conversion failed: #{reason}")}
      end
    end
  end

  @impl true
  def handle_event("clear", _params, socket) do
    {:noreply,
     socket
     |> assign(:x12_content, "")
     |> assign(:json_result, nil)
     |> assign(:validation_result, nil)
     |> assign(:error, nil)
     |> clear_flash()}
  end

  @impl true
  def handle_event("update_content", %{"content" => content}, socket) do
    {:noreply, assign(socket, :x12_content, content)}
  end

  @impl true
  def handle_event("copy_json", _params, socket) do
    {:noreply, push_event(socket, "copy-to-clipboard", %{text: socket.assigns.json_result})}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :x12_file, ref)}
  end

  @impl true
  def handle_event("upload_file", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :x12_file, fn %{path: path}, _entry ->
        case File.read(path) do
          {:ok, content} -> {:ok, content}
          {:error, reason} -> {:postpone, reason}
        end
      end)

    case uploaded_files do
      [content | _] ->
        {:noreply,
         socket
         |> assign(:x12_content, content)
         |> put_flash(:info, "File uploaded successfully")}

      [] ->
        {:noreply, put_flash(socket, :error, "No file uploaded")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app_layout flash={@flash}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Flash Messages -->
      <%= if Phoenix.Flash.get(@flash, :info) do %>
        <div class="mb-4 p-4 bg-green-50 border border-green-200 rounded-lg">
          <p class="text-green-800"><%= Phoenix.Flash.get(@flash, :info) %></p>
        </div>
      <% end %>
      <%= if Phoenix.Flash.get(@flash, :error) do %>
        <div class="mb-4 p-4 bg-red-50 border border-red-200 rounded-lg">
          <p class="text-red-800"><%= Phoenix.Flash.get(@flash, :error) %></p>
        </div>
      <% end %>

      <div class="mb-8">
        <h1 class="text-3xl font-bold text-white">X12 EDI Converter</h1>
        <p class="mt-2 text-gray-300">
          Upload or paste X12 837P/837I/837D files to convert them to semantic JSON
        </p>
      </div>

      <!-- Sample Files -->
      <div class="mb-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
        <h3 class="text-sm font-medium text-blue-900 mb-2">Try Sample Files:</h3>
        <div class="flex gap-3">
          <button
            phx-click="load_sample"
            phx-value-type="837p"
            class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition"
          >
            Load 837P Sample (Professional)
          </button>
          <button
            phx-click="load_sample"
            phx-value-type="837i"
            class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition"
          >
            Load 837I Sample (Institutional)
          </button>
          <button
            phx-click="load_sample"
            phx-value-type="837d"
            class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition"
          >
            Load 837D Sample (Dental)
          </button>
        </div>
      </div>

      <!-- File Upload -->
      <div class="mb-6 bg-white shadow rounded-lg p-6">
        <h3 class="text-lg font-medium text-gray-900 mb-4">Upload X12 File</h3>
        <form phx-submit="upload_file" phx-change="validate_upload" class="space-y-4">
          <div class="border-2 border-dashed border-gray-300 rounded-lg p-6">
            <.live_file_input upload={@uploads.x12_file} class="hidden" />
            <label
              for={@uploads.x12_file.ref}
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
                >
                </path>
              </svg>
              <span class="mt-2 text-sm text-gray-600">
                Click to upload or drag and drop
              </span>
              <span class="mt-1 text-xs text-gray-500">
                .x12, .edi, or .txt files
              </span>
            </label>
          </div>

          <%= for entry <- @uploads.x12_file.entries do %>
            <div class="flex items-center justify-between bg-gray-50 p-3 rounded">
              <span class="text-sm text-gray-700"><%= entry.client_name %></span>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="text-red-600 hover:text-red-800"
              >
                Remove
              </button>
            </div>
          <% end %>

          <button
            :if={length(@uploads.x12_file.entries) > 0}
            type="submit"
            class="w-full px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 transition"
          >
            Upload File
          </button>
        </form>
      </div>

      <!-- X12 Content Input -->
      <div class="mb-6 bg-white shadow rounded-lg p-6">
        <div class="flex justify-between items-center mb-4">
          <h3 class="text-lg font-medium text-gray-900">X12 Content</h3>
          <button
            phx-click="clear"
            class="px-3 py-1 text-sm bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
          >
            Clear
          </button>
        </div>
        <%= if @x12_content != "" do %>
          <div class="mb-2 text-xs text-gray-500">
            Loaded X12 content (<%= String.length(@x12_content) %> characters)
          </div>
          <pre class="w-full px-3 py-2 border border-gray-300 rounded-md font-mono text-sm text-gray-900 bg-gray-50 overflow-x-auto whitespace-pre-wrap min-h-[200px]"><%= @x12_content %></pre>
        <% else %>
          <.form for={%{}} phx-change="update_content">
            <textarea
              id="x12-content-textarea"
              name="content"
              phx-debounce="300"
              rows="12"
              class="w-full px-3 py-2 border border-gray-300 rounded-md font-mono text-sm"
              placeholder="Paste X12 EDI content here or use the buttons above to load sample data..."
            ><%= @x12_content %></textarea>
          </.form>
        <% end %>
      </div>

      <!-- Action Buttons -->
      <div class="mb-6 flex gap-3">
        <button
          phx-click="validate"
          disabled={@processing}
          class="px-6 py-2 bg-yellow-600 text-white rounded-md hover:bg-yellow-700 transition disabled:opacity-50"
        >
          Validate Only
        </button>
        <button
          phx-click="convert"
          disabled={@processing}
          class="px-6 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 transition disabled:opacity-50"
        >
          <%= if @processing, do: "Converting...", else: "Validate & Convert to JSON" %>
        </button>
      </div>

      <!-- Validation Results -->
      <%= if @validation_result do %>
        <div class="mb-6 bg-white shadow rounded-lg p-6">
          <h3 class="text-lg font-medium text-gray-900 mb-4">Validation Results</h3>

          <div class="mb-4">
            <span class={[
              "px-3 py-1 rounded-full text-sm font-medium",
              if(@validation_result.valid?,
                do: "bg-green-100 text-green-800",
                else: "bg-red-100 text-red-800"
              )
            ]}>
              <%= if @validation_result.valid?, do: "✓ VALID", else: "✗ INVALID" %>
            </span>
            <span class="ml-4 text-sm text-gray-600">
              <%= @validation_result.segment_count %> segments processed
            </span>
          </div>

          <%= if length(@validation_result.issues) > 0 do %>
            <div class="space-y-2">
              <%= for issue <- Enum.reverse(@validation_result.issues) do %>
                <div class={[
                  "p-3 rounded border-l-4",
                  case issue.level do
                    :error -> "bg-red-50 border-red-500"
                    :warning -> "bg-yellow-50 border-yellow-500"
                    :info -> "bg-blue-50 border-blue-500"
                  end
                ]}>
                  <div class="flex items-start">
                    <span class="font-mono text-xs text-gray-500 mr-3">
                      [<%= issue.segment_id %>:<%= issue.segment_number %>]
                    </span>
                    <span class="text-sm flex-1"><%= issue.message %></span>
                  </div>
                  <%= if issue.context != "" do %>
                    <div class="mt-1 ml-20 text-xs text-gray-600">
                      <%= issue.context %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-sm text-green-600">No validation issues found!</p>
          <% end %>
        </div>
      <% end %>

      <!-- JSON Result -->
      <%= if @json_result do %>
        <div class="bg-white shadow rounded-lg p-6">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-lg font-medium text-gray-900">JSON Output</h3>
            <div class="flex gap-2">
              <a
                href={"data:application/json;charset=utf-8,#{URI.encode(@json_result)}"}
                download="x12_converted.json"
                class="px-3 py-1 text-sm bg-green-600 text-white rounded hover:bg-green-700"
              >
                Download JSON
              </a>
              <button
                onclick={"navigator.clipboard.writeText(`#{String.replace(@json_result, "`", "\\`")}`).then(() => alert('Copied to clipboard!'))"}
                class="px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"
              >
                Copy JSON
              </button>
            </div>
          </div>
          <pre class="bg-gray-900 text-green-400 p-4 rounded overflow-x-auto text-sm"><%= @json_result %></pre>
        </div>
      <% end %>

      <%= if @error do %>
        <div class="mt-6 bg-red-50 border border-red-200 rounded-lg p-4">
          <p class="text-red-800"><%= @error %></p>
        </div>
      <% end %>
    </div>
    </.app_layout>
    """
  end
end
