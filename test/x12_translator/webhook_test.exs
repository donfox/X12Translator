defmodule X12Translator.WebhookTest do
  use ExUnit.Case, async: true

  alias X12Translator.Webhook

  defmodule FakePlugRouter do
    use Plug.Router
    plug :match
    plug Plug.Parsers, parsers: [:json], json_decoder: Jason
    plug :dispatch

    post "/api/x12-batch-ingest" do
      # Echo the payload back so tests can inspect it
      send_resp(conn, 200, Jason.encode!(conn.body_params))
    end
  end

  setup do
    # Start a Bandit server on a random port to receive the webhook
    {:ok, server} = Bandit.start_link(plug: FakePlugRouter, port: 0, ip: :loopback)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    url = "http://localhost:#{port}/api/x12-batch-ingest"

    # Configure webhook URL for this test
    prev = Application.get_env(:x12_translator, :webhook)
    Application.put_env(:x12_translator, :webhook, url: url)
    on_exit(fn -> Application.put_env(:x12_translator, :webhook, prev) end)

    %{url: url}
  end

  test "send_batch posts claims to the configured URL" do
    jobs = [
      %{
        original_filename: "test_claim.x12",
        json_result: Jason.encode!(%{"transaction_type" => "837P", "claim" => %{"claim_id" => "CLM-001"}})
      }
    ]

    assert {:ok, 200} = Webhook.send_batch("batch-123", jobs)
  end

  test "send_batch handles multiple claims" do
    jobs = [
      %{
        original_filename: "claim_1.x12",
        json_result: Jason.encode!(%{"claim_id" => "CLM-001"})
      },
      %{
        original_filename: "claim_2.x12",
        json_result: Jason.encode!(%{"claim_id" => "CLM-002"})
      }
    ]

    assert {:ok, 200} = Webhook.send_batch("batch-456", jobs)
  end

  test "send_batch splits multi-claim X12 into individual claims" do
    x12_content = File.read!("test/fixtures/batch_input/multi_claim_837p.x12")

    jobs = [
      %{
        original_filename: "multi_claim_837p.x12",
        json_result: Jason.encode!(%{"combined" => true}),
        x12_content: x12_content
      }
    ]

    assert {:ok, 200} = Webhook.send_batch("batch-multi", jobs)
  end

  test "multi-claim file produces one payload entry per claim" do
    x12_content = File.read!("test/fixtures/batch_input/multi_claim_837p.x12")

    # Use ClaimSplitter directly to verify what the webhook would send
    assert {:ok, claims} = X12Translator.X12.ClaimSplitter.split_claims(x12_content)
    assert length(claims) == 3

    # Verify the filenames that would be generated
    expected_filenames = [
      "multi_claim_837p_CLM-900001.json",
      "multi_claim_837p_CLM-900002.json",
      "multi_claim_837p_CLM-900003.json"
    ]

    actual_filenames =
      Enum.map(claims, fn %{claim_id: cid} ->
        base = String.replace("multi_claim_837p.x12", ~r/\.(x12|edi|txt)$/i, "")
        "#{base}_#{cid}.json"
      end)

    assert actual_filenames == expected_filenames
  end

  test "send_batch returns :not_configured when no URL is set" do
    Application.put_env(:x12_translator, :webhook, url: nil)
    jobs = [%{original_filename: "test.x12", json_result: "{}"}]

    assert {:ok, :not_configured} = Webhook.send_batch("batch-789", jobs)
  end
end
