defmodule PCA9622Matrix8x8.Demo do
  @moduledoc """
  Sample GenServer that counts up once a second and shows the current
  number on the matrix via `PCA9622Matrix8x8.CharGen`.
  """

  use GenServer
  require Logger
  Logger.metadata(module: __MODULE__)

  def start_link(ms \\ 0) do
    GenServer.start_link(__MODULE__, ms, name: __MODULE__)
  end

  @impl true
  @doc false
  def init(ms) do
    # Start the LED matrix GenServer
    PCA9622Matrix8x8.start_link(reflesh_interval: ms)
    Logger.info("#{__MODULE__} started:")
    # Send a :tick message every second
    Process.send_after(self(), :tick, 1000)
    # Initial state is 0
    {:ok, 0}
  end

  @impl true
  @doc false
  def handle_info(:tick, n) do
    Logger.info("Current number: #{n}")
    # Show the number on the LED matrix
    PCA9622Matrix8x8.CharGen.digit_strlist(n)
    |> PCA9622Matrix8x8.CharGen.strlist_tuples()
    |> PCA9622Matrix8x8.set_matrix()

    # Schedule the next tick
    Process.send_after(self(), :tick, 1000)
    # Update the state to n + 1
    {:noreply, n + 1}
  end

  def stop() do
    # Stop the LED matrix GenServer
    PCA9622Matrix8x8.stop()
    # Stop this GenServer too
    GenServer.stop(__MODULE__, :normal)
    :ok
  end
end
