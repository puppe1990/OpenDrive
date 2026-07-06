defmodule OpenDriveWeb.DirectUploadErrors do
  @moduledoc false

  use Gettext, backend: OpenDriveWeb.Gettext

  def response(:db_busy) do
    {503,
     %{
       "error" =>
         gettext("The database is busy finalizing other uploads. Wait a few seconds and retry.")
     }}
  end
end
