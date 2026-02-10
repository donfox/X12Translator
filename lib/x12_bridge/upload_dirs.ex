defmodule X12Bridge.UploadDirs do
  @moduledoc """
  Resolves and ensures per-user upload directories exist.
  """

  alias X12Bridge.UsernameSanitizer

  @spec resolve(String.t() | nil) :: {String.t(), String.t()}
  def resolve(username) do
    base = base_dir()
    sanitized = UsernameSanitizer.sanitize(username)
    input_dir = Path.join([base, sanitized, "input"])
    output_dir = Path.join([base, sanitized, "output"])
    {input_dir, output_dir}
  end

  @spec ensure(String.t() | nil) :: {String.t(), String.t()}
  def ensure(username) do
    {input_dir, output_dir} = resolve(username)
    File.mkdir_p!(input_dir)
    File.mkdir_p!(output_dir)
    {input_dir, output_dir}
  end

  defp base_dir do
    config = Application.get_env(:x12_bridge, :web_uploads, [])
    Keyword.get(config, :base_dir, "priv/uploads")
  end
end
