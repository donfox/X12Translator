defmodule X12BridgeWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use X12BridgeWeb, :html

  embed_templates "page_html/*"
end
