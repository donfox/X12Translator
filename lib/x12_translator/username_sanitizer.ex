defmodule X12Translator.UsernameSanitizer do
  @moduledoc """
  Sanitizes usernames into filesystem-safe directory names.
  """

  @spec sanitize(String.t() | nil) :: String.t()
  def sanitize(nil), do: "anonymous"
  def sanitize(""), do: "anonymous"

  def sanitize(name) when is_binary(name) do
    result =
      name
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/, "_")
      |> String.replace(~r/[^a-z0-9_\-]/, "")
      |> String.replace(~r/_{2,}/, "_")
      |> String.trim("_")
      |> String.slice(0..49)

    if result == "", do: "anonymous", else: result
  end
end
