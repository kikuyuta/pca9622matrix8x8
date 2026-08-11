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

  def init(ms) do
    PCA9622Matrix8x8.start_link(reflesh_interval: ms) # Start the LED matrix GenServer
    Logger.info("#{__MODULE__} started:")
    Process.send_after(self(), :tick, 1000) # Send a :tick message every second
    {:ok, 0} # Initial state is 0
  end

  def handle_info(:tick, n) do
    Logger.info("Current number: #{n}")
    # Show the number on the LED matrix
    PCA9622Matrix8x8.CharGen.digit_strlist(n)
    |> PCA9622Matrix8x8.CharGen.strlist_tuples()
    |> PCA9622Matrix8x8.set_matrix()
    Process.send_after(self(), :tick, 1000) # Schedule the next tick
    {:noreply, n + 1} # Update the state to n + 1
  end

  def stop() do
    PCA9622Matrix8x8.stop() # Stop the LED matrix GenServer
    GenServer.stop(__MODULE__, :normal) # Stop this GenServer too
    :ok
  end
end
