defmodule X12TranslatorWeb.TranslateController do
  @moduledoc """
  REST API endpoint for submitting X12 EDI files for translation.

  Accepts multipart file uploads, creates a batch, and processes
  asynchronously through verify → translate → webhook pipeline.

  The caller receives an immediate acknowledgment with the batch_id.
  Translated results are delivered via webhook to the configured endpoint.
  """

  use X12TranslatorWeb, :controller

  alias X12Translator.Conversions

  @accepted_extensions ~w(.x12 .edi .txt)

  def create(conn, %{"files" => files}) when is_list(files) do
    # Filter to accepted file types
    valid_files =
      Enum.filter(files, fn upload ->
        ext = upload.filename |> Path.extname() |> String.downcase()
        ext in @accepted_extensions
      end)

    if valid_files == [] do
      conn
      |> put_status(422)
      |> json(%{error: "No valid X12 files provided", accepted_extensions: @accepted_extensions})
    else
      # Read file contents
      file_entries =
        Enum.map(valid_files, fn upload ->
          content = File.read!(upload.path)
          %{filename: upload.filename, content: content, size: byte_size(content)}
        end)

      # Create batch
      batch_name = Map.get(conn.params, "batch_name", "API Upload #{DateTime.utc_now()}")
      submitted_by = Map.get(conn.params, "submitted_by", "rest_api")

      {:ok, batch} =
        Conversions.create_batch(%{
          name: batch_name,
          submitted_by: submitted_by,
          total_files: length(file_entries),
          status: "uploaded"
        })

      # Create jobs for each file
      uploaded_files =
        Enum.reduce(file_entries, %{}, fn entry, acc ->
          {:ok, job} =
            Conversions.create_job(%{
              batch_id: batch.id,
              original_filename: entry.filename,
              file_size: entry.size,
              status: "uploaded",
              x12_content: entry.content
            })

          Map.put(acc, job.id, entry.content)
        end)

      # Process asynchronously: verify → translate → webhook
      Task.Supervisor.start_child(X12Translator.TaskSupervisor, fn ->
        process_translate_pipeline(batch.id, uploaded_files)
      end)

      conn
      |> put_status(202)
      |> json(%{
        batch_id: batch.id,
        status: "accepted",
        file_count: length(file_entries),
        message: "Files submitted for translation. Results will be delivered via webhook."
      })
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{
      error: "Missing files",
      usage: "POST /api/translate with multipart form data containing 'files[]' field"
    })
  end

  def show(conn, %{"batch_id" => batch_id}) do
    try do
      batch = Conversions.get_batch!(batch_id)

      conn
      |> put_status(200)
      |> json(%{
        batch_id: batch.id,
        status: batch.status,
        total_files: batch.total_files,
        verified_files: batch.verified_files,
        translated_files: batch.translated_files,
        failed_files: batch.failed_files
      })
    rescue
      Ecto.NoResultsError ->
        conn
        |> put_status(404)
        |> json(%{error: "Batch not found"})
    end
  end

  # Runs the full verify → translate pipeline.
  # On completion, translate_batch_sync triggers the webhook automatically.
  defp process_translate_pipeline(batch_id, uploaded_files) do
    require Logger

    Logger.info("API translate pipeline starting for batch #{batch_id}")

    # Stage 1: Verify
    {:ok, batch} = Conversions.verify_batch_sync(batch_id, uploaded_files)
    verified_count = batch.verified_files || 0

    if verified_count > 0 do
      # Stage 2: Translate (also fires webhook on completion)
      Conversions.translate_batch_sync(batch_id, uploaded_files)
      Logger.info("API translate pipeline completed for batch #{batch_id}")
    else
      Logger.warning("API translate pipeline: no files passed verification for batch #{batch_id}")
    end
  end
end
