defmodule RapidTools.ConversionStore do
  @moduledoc false

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def put(entry) do
    id = System.unique_integer([:positive]) |> Integer.to_string(36)

    Agent.update(__MODULE__, &Map.put(&1, id, entry))
    {:ok, id}
  end

  def put_batch(entries) when is_list(entries) do
    id = System.unique_integer([:positive]) |> Integer.to_string(36)

    Agent.update(__MODULE__, &Map.put(&1, batch_key(id), entries))
    {:ok, id}
  end

  def fetch(id) do
    case Agent.get(__MODULE__, &Map.get(&1, id)) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  def fetch_batch(id) do
    case Agent.get(__MODULE__, &Map.get(&1, batch_key(id))) do
      nil -> {:error, :not_found}
      entries -> {:ok, entries}
    end
  end

  defp batch_key(id), do: "batch:" <> id
end
