defmodule X12Translator.Webhook do
  @moduledoc """
  Sends translated claim JSON to external systems via HTTP POST.

  Multi-claim X12 files are split into individual claims before sending,
  so each entry in the payload represents exactly one claim.
  """

  require Logger

  alias X12Translator.X12.{ClaimSplitter, Converter, SegmentMapper}

  @doc """
  Posts a batch of translated claims to the configured webhook endpoint.

  Payload format:

      %{
        "batch_id" => batch_id,
        "claims" => [
          %{"filename" => "file.x12", "claim" => %{...semantic_json...}},
          ...
        ]
      }

  Returns `{:ok, response}` on success (2xx), `{:error, reason}` otherwise.
  """
  def send_batch(batch_id, jobs) do
    url = webhook_url()

    if url do
      claims = Enum.flat_map(jobs, &expand_job_claims/1)

      payload = %{"batch_id" => batch_id, "claims" => claims}

      Logger.info("Webhook POST to #{url} — batch #{batch_id}, #{length(claims)} claim(s)")

      case Req.post(url, json: payload, receive_timeout: 30_000) do
        {:ok, %Req.Response{status: status}} when status in 200..299 ->
          Logger.info("Webhook succeeded for batch #{batch_id} (HTTP #{status})")
          {:ok, status}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.warning(
            "Webhook failed for batch #{batch_id} — HTTP #{status}: #{inspect(body)}"
          )

          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.warning("Webhook request failed for batch #{batch_id}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.debug("Webhook not configured, skipping POST for batch #{batch_id}")
      {:ok, :not_configured}
    end
  end

  # Splits a job into individual claim entries for the webhook payload.
  # Multi-claim X12 files produce one entry per claim; single-claim files
  # produce one entry using the original filename.
  defp expand_job_claims(job) do
    if Map.get(job, :x12_content) do
      case ClaimSplitter.split_claims_to_x12(job.x12_content) do
        {:ok, nil} ->
          [%{"filename" => to_json_filename(job.original_filename),
             "claim" => decode_json_result(job.json_result)}]

        {:ok, claims} ->
          Enum.flat_map(claims, fn %{claim_id: claim_id, x12_content: x12} ->
            with {:ok, flat_json} <- Converter.convert_content(x12),
                 {:ok, semantic} <- SegmentMapper.map_from_json(flat_json) do
              [%{"filename" => to_split_filename(job.original_filename, claim_id),
                 "claim" => semantic}]
            else
              {:error, reason} ->
                Logger.warning("Conversion failed for split claim #{claim_id} in #{job.original_filename}: #{inspect(reason)}")
                []
            end
          end)

        {:error, reason} ->
          Logger.warning("Claim splitting failed for #{job.original_filename}: #{inspect(reason)}, sending unsplit")
          [%{"filename" => to_json_filename(job.original_filename),
             "claim" => decode_json_result(job.json_result)}]
      end
    else
      [%{"filename" => to_json_filename(job.original_filename),
         "claim" => decode_json_result(job.json_result)}]
    end
  end

  defp to_json_filename(filename) do
    String.replace(filename, ~r/\.(x12|edi|txt)$/i, ".json")
  end

  defp to_split_filename(original_filename, claim_id) do
    base = String.replace(original_filename, ~r/\.(x12|edi|txt)$/i, "")
    "#{base}_#{claim_id}.json"
  end

  defp webhook_url do
    Application.get_env(:x12_translator, :webhook)[:url]
  end

  defp decode_json_result(json_result) when is_binary(json_result) do
    case Jason.decode(json_result) do
      {:ok, decoded} -> decoded
      {:error, _} -> json_result
    end
  end

  defp decode_json_result(other), do: other
end
