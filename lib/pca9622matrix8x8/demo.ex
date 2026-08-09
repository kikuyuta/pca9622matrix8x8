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
    PCA9622Matrix8x8.start_link(ms) # LEDマトリクスのGenServerを起動
    Logger.info("#{__MODULE__} started:")
    Process.send_after(self(), :tick, 1000) # 1秒ごとに :tick メッセージを送る
    {:ok, 0} # 初期状態は0
  end

  def handle_info(:tick, n) do
    Logger.info("Current number: #{n}")
    # 数字をLEDマトリクスに表示
    PCA9622Matrix8x8.CharGen.digit_strlist(n)
    |> PCA9622Matrix8x8.CharGen.strlist_tuples()
    |> PCA9622Matrix8x8.set_matrix()
    Process.send_after(self(), :tick, 1000) # 次の tick をスケジュール
    {:noreply, n + 1} # 状態を n + 1 に更新
  end

  def stop() do
    PCA9622Matrix8x8.stop() # LEDマトリクスのGenServerを停止
    GenServer.stop(__MODULE__, :normal) # 自身のGenServerも停止
    :ok
  end
end
