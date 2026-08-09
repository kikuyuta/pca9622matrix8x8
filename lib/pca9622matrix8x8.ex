defmodule PCA9622Matrix8x8 do
  @moduledoc """
  Driver for the switch-science "I2C 8x8 LED matrix" board
  (https://www.switch-science.com/products/2071), which multiplexes an
  8x8 LED matrix over I2C using the PCA9622 constant-current LED driver.
  """

  use GenServer
  require Logger

  @i2c_address 0x50 # default for PCA9622

  # PCA9622 レジスタアドレス
  @mode1 0x00
  @mode2 0x01
#  @pwm0 0x02
  @ledout0 0x14
  @ledout1 0x15
  @ledout2 0x16
  @ledout3 0x17

  @default_reflesh_interval 10 # ms

  def start_link(reflesh_interval \\ @default_reflesh_interval) do
    GenServer.start_link(__MODULE__, {nil, reflesh_interval}, name: __MODULE__)
  end

  def init({initial_matrix, reflesh_interval}) do
    Logger.info("Initializing LED Matrix GenServer")
    # シグナルトラップを有効にして、異常終了時にもクリーンアップが実行されるようにする
    Process.flag(:trap_exit, true)
    {:ok, ref} = Circuits.I2C.open("i2c-2")
    Circuits.I2C.write(ref, @i2c_address, <<@mode1, 0x00>>)
    Circuits.I2C.write(ref, @i2c_address, <<@mode2, 0x55>>)
    new_mat = if is_nil(initial_matrix), do: set_matrix_all(0), else: initial_matrix
    Process.send_after(self(), :dyn_wait, reflesh_interval)
    {:ok, {ref, new_mat, 0, reflesh_interval}}
  end

  def set_matrix(mat) do
    GenServer.cast(__MODULE__, {:set_matrix, mat})
  end

  def set_matrix_bit(x, y, value) do
    GenServer.cast(__MODULE__, {:set_matrix_bit, x, y, value})
  end

  def set_interval(interval) do
    GenServer.cast(__MODULE__, {:set_interval, interval})
  end

  def handle_cast({:set_interval, interval}, {ref, mat, counter, _old_interval}) do
    {:noreply, {ref, mat, counter, interval}}
  end

  def handle_cast({:set_matrix, mat}, {ref, _old_mat, counter, reflesh_interval}) do
    # mat は 8x8 の行列 (tuple の tuple) と仮定
    # Logger.debug("Updating entire matrix")
    {:noreply, {ref, mat, counter, reflesh_interval}}
  end

  def handle_cast({:set_matrix_bit, x, y, value}, {ref, old_mat, counter, reflesh_interval}) do
    new_row = put_elem(elem(old_mat, y), x, value)
    new_mat = put_elem(old_mat, y, new_row)
    {:noreply, {ref, new_mat, counter, reflesh_interval}}
  end

  def set_matrix_all(value) do # 8x8の行列を指定された値で初期化
    new_value =if is_integer(value) and value in [0, 1] do
      value
    else
      if value, do: 1, else: 0
    end

    (for _ <- 0..7, do: List.duplicate(new_value, 8) |> List.to_tuple()) |> List.to_tuple()
  end

  def handle_info(:dyn_wait, {ref, mat, counter, reflesh_interval}) do
    {:noreply, {ref, mat, counter, reflesh_interval}, {:continue, :update_leds}}
  end

  def handle_info({:EXIT, _from, reason}, {ref, mat, counter, reflesh_interval}) do
    Logger.info("Received EXIT signal with reason: #{inspect(reason)}, cleaning up LED Matrix")
    stop_led(ref)
    {:stop, reason, {ref, mat, counter, reflesh_interval}}
  end

  def handle_continue(:update_leds, {ref, mat, counter, reflesh_interval}) do
    # 元の表示を消去（これを入れないと元の列に残像が残る）
    {row_high, row_low} = bit_expand({0,0,0,0,0,0,0,0})
#    {col_high, col_low} = bit_expand(counter)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout0, row_low::binary>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout1, row_high::binary>>)
#    Circuits.I2C.write(ref, @i2c_address, <<@ledout2, col_low::binary>>)
#    Circuits.I2C.write(ref, @i2c_address, <<@ledout3, col_high::binary>>)

    # 次の列を表示
    new_counter = rem(counter + 1, 8) # 0〜7の範囲でカウンターをループさせる
    {row_high, row_low} = bit_expand(elem(mat, new_counter))
    {col_high, col_low} = bit_expand(new_counter)

    Circuits.I2C.write(ref, @i2c_address, <<@ledout2, col_low::binary>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout3, col_high::binary>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout0, row_low::binary>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout1, row_high::binary>>)

    Process.send_after(self(), :dyn_wait, reflesh_interval)
    {:noreply, {ref, mat, new_counter, reflesh_interval}}
  end

  def bit_expand({b7, b6, b5, b4, b3, b2, b1, b0}) do
    # row は 8ビットの整数と仮定 (例えば、0b10101010)
    # 各ビットを2ビットに展開して、2バイトの tupleを返す
    # 例えば、ビットが1なら '00' (0x00)、0なら '01' (0x01) とする
    high = <<enbit(b7)::2, enbit(b6)::2, enbit(b5)::2, enbit(b4)::2>>
    low  = <<enbit(b3)::2, enbit(b2)::2, enbit(b1)::2, enbit(b0)::2>>
    {high, low}
  end

  def bit_expand(7), do: {<<0x55>>, <<0x54>>}
  def bit_expand(6), do: {<<0x55>>, <<0x51>>}
  def bit_expand(5), do: {<<0x55>>, <<0x45>>}
  def bit_expand(4), do: {<<0x55>>, <<0x15>>}
  def bit_expand(3), do: {<<0x54>>, <<0x55>>}
  def bit_expand(2), do: {<<0x51>>, <<0x55>>}
  def bit_expand(1), do: {<<0x45>>, <<0x55>>}
  def bit_expand(0), do: {<<0x15>>, <<0x55>>}

  def bit_expand(x) do
   Logger.error("Invalid input for bit_expand: #{inspect(x)}. Expected a tuple of 8 bits.")
   {<<0x55>>, <<0x55>>} # 全てOFFの状態を返す
  end

  defp enbit(0), do: 0b01 # LED OFF
  defp enbit(1), do: 0b00 # LED ON
  defp enbit(n) do
    Logger.error("Invalid bit value: #{inspect(n)}. Expected 0 or 1.")
    0b01 # デフォルトはOFF
  end

  def stop() do
    GenServer.stop(__MODULE__, :normal)
  end

  def terminate(_reason, {ref, _mat, _counter, _reflesh_interval}) do
    stop_led(ref) # LEDを全てOFFにしてI2Cバスをクローズ
    Logger.info("Terminating LED Matrix GenServer")
    :ok
  end

# 以降は主に GenServer の外で直接呼び出す関数群

def init_led() do
    {:ok, ref} = Circuits.I2C.open("i2c-2")
    Circuits.I2C.write(ref, @i2c_address, <<@mode1, 0x00>>)
    Circuits.I2C.write(ref, @i2c_address, <<@mode2, 0x55>>)
    ref
  end

  def stop_led(ref) do
    all_off(ref)
    Circuits.I2C.close(ref)
  end


  def set_xyzw(ref, x, y, z, w) do
    Circuits.I2C.write(ref, @i2c_address, <<@ledout0, x>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout1, y>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout2, z>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout3, w>>)
  end

  def set_00(ref) do
    Circuits.I2C.write(ref, @i2c_address, <<@ledout0, 0x51>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout1, 0x55>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout2, 0x51>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout3, 0x55>>)
  end

  def read_led(ref, offset) do
    Circuits.I2C.read(ref, @i2c_address, <<@ledout0 + offset>>)
    |> :binary.decode_unsigned()
    |> IO.inspect(label: "Read LED Register #{offset}")
  end

  def all_on(ref) do
    Circuits.I2C.write(ref, @i2c_address, <<@ledout0, 0x00>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout1, 0x00>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout2, 0x00>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout3, 0x00>>)
  end

  def all_off(ref) do
    Circuits.I2C.write(ref, @i2c_address, <<@ledout0, 0x55>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout1, 0x55>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout2, 0x00>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout3, 0x00>>)
  end

  def test_start() do
    # 1. I2Cバスのオープン (環境に合わせて "i2c-1" などに変更)
    {:ok, ref} = Circuits.I2C.open("i2c-2")

    # 2. 初期化: SLEEP解除 (MODE1レジスタ)
    Circuits.I2C.write(ref, @i2c_address, <<@mode1, 0x00>>)
    # Circuits.I2C.write(ref, @i2c_address, <<@mode2, 0x05>>)

    # 3. 全てのLEDピンを「PWM制御モード」に設定 (0〜3)
    # 0xAA は 2進数で 10101010 (各ピン2ビットで '10' = PWMモード)
    # Enum.each(0..3, fn offset ->
    #   Circuits.I2C.write(ref, @i3c_address, <<@pwm0 + offset, 0x55>>)
    # end)
    # これはじっさいにはやってないのであってるかは不明。
    test_loop(ref)
  end

  def test_loop(ref) do
    Circuits.I2C.write(ref, @i2c_address, <<@ledout0, 0x00>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout1, 0x00>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout2, 0x00>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout3, 0x00>>)
    IO.puts("LEDs should be On now.")
    Process.sleep(1000)

    Circuits.I2C.write(ref, @i2c_address, <<@ledout0, 0x55>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout1, 0x55>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout2, 0x00>>)
    Circuits.I2C.write(ref, @i2c_address, <<@ledout3, 0x00>>)
    IO.puts("LEDs should be Off now.")
    Process.sleep(1000)

    test_loop(ref)
  end
end
