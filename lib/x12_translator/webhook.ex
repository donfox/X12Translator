defmodule X12Translator.Webhook do
  @moduledoc """
  Sends translated claim JSON to external systems via HTTP POST.
  """

  require Logger

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
      claims =
        Enum.map(jobs, fn job ->
          %{
            "filename" => job.original_filename,
            "claim" => decode_json_result(job.json_result)
          }
        end)

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
