defmodule X12Translator.Repo.Migrations.AddRemoteMetadataToJobs do
  use Ecto.Migration

  def change do
    alter table(:conversion_jobs) do
      add :remote_host, :string, comment: "Remote server hostname"
      add :remote_path, :text, comment: "Remote file path"
      add :remote_source_url, :text, comment: "Remote source URL"
    end
  end
end
