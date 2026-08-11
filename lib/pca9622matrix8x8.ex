defmodule PCA9622Matrix8x8 do
  @moduledoc """
  Driver for the switch-science "I2C 8x8 LED matrix" board
  (https://www.switch-science.com/products/2071), which multiplexes an
  8x8 LED matrix over I2C using the PCA9622 constant-current LED driver.

  `start_link/1` accepts:

    * `:bus_name` - the I2C bus to open (default: `"i2c-2"`)
    * `:i2c_address` - the PCA9622's I2C address (default: `0x50`)
    * `:reflesh_interval` - column refresh interval in ms (default: `10`)
    * `:initial_matrix` - initial 8x8 matrix to display
    * `:name` - GenServer name to register under (default: `#{inspect(__MODULE__)}`);
      pass `nil` to start unnamed, which allows multiple boards to run at once.
      When a name other than the default is used (or `nil`), pass the returned
      pid/name explicitly to `set_matrix/2`, `set_matrix_bit/4` and `stop/1`.
  """

  use GenServer
  require Logger

  @default_bus_name "i2c-2"
  # default for PCA9622
  @default_i2c_address 0x50

  # PCA9622 register addresses
  @mode1 0x00
  @mode2 0x01
  #  @pwm0 0x02
  @ledout0 0x14
  @ledout1 0x15
  @ledout2 0x16
  @ledout3 0x17

  # ms
  @default_reflesh_interval 10

  @doc """
  Starts the LED matrix driver GenServer. See the moduledoc for available
  `opts`.
  """
  def start_link(opts \\ []) when is_list(opts) do
    bus_name = Keyword.get(opts, :bus_name, @default_bus_name)
    i2c_address = Keyword.get(opts, :i2c_address, @default_i2c_address)
    reflesh_interval = Keyword.get(opts, :reflesh_interval, @default_reflesh_interval)
    initial_matrix = Keyword.get(opts, :initial_matrix)

    gen_opts =
      case Keyword.get(opts, :name, __MODULE__) do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(
      __MODULE__,
      {bus_name, i2c_address, initial_matrix, reflesh_interval},
      gen_opts
    )
  end

  @impl true
  @doc false
  def init({bus_name, i2c_address, initial_matrix, reflesh_interval}) do
    Logger.info(
      "Initializing LED Matrix GenServer on #{bus_name} at 0x#{Integer.to_string(i2c_address, 16)}"
    )

    # Trap exits so cleanup still runs on abnormal termination
    Process.flag(:trap_exit, true)
    {:ok, ref} = Circuits.I2C.open(bus_name)
    Circuits.I2C.write(ref, i2c_address, <<@mode1, 0x00>>)
    Circuits.I2C.write(ref, i2c_address, <<@mode2, 0x55>>)
    new_mat = if is_nil(initial_matrix), do: set_matrix_all(0), else: initial_matrix
    Process.send_after(self(), :dyn_wait, reflesh_interval)
    {:ok, {ref, i2c_address, new_mat, 0, reflesh_interval}}
  end

  @doc """
  Replaces the whole 8x8 matrix that is currently displayed.

  `mat` is an 8x8 tuple of tuples of `0`/`1`, e.g. as built from
  `PCA9622Matrix8x8.CharGen.digit_strlist/2` output.
  """
  def set_matrix(server \\ __MODULE__, mat) do
    GenServer.cast(server, {:set_matrix, mat})
  end

  @doc """
  Sets a single pixel `(x, y)` of the currently displayed matrix to `value`
  (`0` or `1`).
  """
  def set_matrix_bit(server \\ __MODULE__, x, y, value) do
    GenServer.cast(server, {:set_matrix_bit, x, y, value})
  end

  @impl true
  @doc false
  def handle_cast({:set_matrix, mat}, {ref, i2c_address, _old_mat, counter, reflesh_interval}) do
    # mat is assumed to be an 8x8 matrix (tuple of tuples)
    # Logger.debug("Updating entire matrix")
    {:noreply, {ref, i2c_address, mat, counter, reflesh_interval}}
  end

  def handle_cast(
        {:set_matrix_bit, x, y, value},
        {ref, i2c_address, old_mat, counter, reflesh_interval}
      ) do
    new_row = put_elem(elem(old_mat, y), x, value)
    new_mat = put_elem(old_mat, y, new_row)
    {:noreply, {ref, i2c_address, new_mat, counter, reflesh_interval}}
  end

  @doc """
  Builds an 8x8 matrix (as used by `set_matrix/2`) with every pixel set to
  `value`. `value` may be `0`/`1`, or any other term treated as falsy/truthy.
  """
  def set_matrix_all(value) do
    new_value =
      if is_integer(value) and value in [0, 1] do
        value
      else
        if value, do: 1, else: 0
      end

    for(_ <- 0..7, do: List.duplicate(new_value, 8) |> List.to_tuple()) |> List.to_tuple()
  end

  @impl true
  @doc false
  def handle_info(:dyn_wait, {ref, i2c_address, mat, counter, reflesh_interval}) do
    {:noreply, {ref, i2c_address, mat, counter, reflesh_interval}, {:continue, :update_leds}}
  end

  def handle_info(
        {:EXIT, _from, reason},
        {ref, i2c_address, _mat, _counter, _reflesh_interval} = state
      ) do
    Logger.info("Received EXIT signal with reason: #{inspect(reason)}, cleaning up LED Matrix")
    stop_led(ref, i2c_address)
    {:stop, reason, state}
  end

  @impl true
  @doc false
  def handle_continue(:update_leds, {ref, i2c_address, mat, counter, reflesh_interval}) do
    # Clear the previous display (without this, the old column leaves a ghost image)
    {row_high, row_low} = bit_expand({0, 0, 0, 0, 0, 0, 0, 0})
    #    {col_high, col_low} = bit_expand(counter)
    Circuits.I2C.write(ref, i2c_address, <<@ledout0, row_low::binary>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout1, row_high::binary>>)
    #    Circuits.I2C.write(ref, i2c_address, <<@ledout2, col_low::binary>>)
    #    Circuits.I2C.write(ref, i2c_address, <<@ledout3, col_high::binary>>)

    # Display the next column
    # Loop the counter through the range 0-7
    new_counter = rem(counter + 1, 8)
    {row_high, row_low} = bit_expand(elem(mat, new_counter))
    {col_high, col_low} = bit_expand(new_counter)

    Circuits.I2C.write(ref, i2c_address, <<@ledout2, col_low::binary>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout3, col_high::binary>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout0, row_low::binary>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout1, row_high::binary>>)

    Process.send_after(self(), :dyn_wait, reflesh_interval)
    {:noreply, {ref, i2c_address, mat, new_counter, reflesh_interval}}
  end

  @doc false
  def bit_expand({b7, b6, b5, b4, b3, b2, b1, b0}) do
    # row is assumed to be 8 bits (e.g. 0b10101010)
    # Expand each bit into 2 bits and return a tuple of two bytes
    # e.g. a bit of 1 becomes '00' (0x00), and 0 becomes '01' (0x01)
    high = <<enbit(b7)::2, enbit(b6)::2, enbit(b5)::2, enbit(b4)::2>>
    low = <<enbit(b3)::2, enbit(b2)::2, enbit(b1)::2, enbit(b0)::2>>
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
    # Return the all-OFF state
    {<<0x55>>, <<0x55>>}
  end

  # LED OFF
  defp enbit(0), do: 0b01
  # LED ON
  defp enbit(1), do: 0b00

  defp enbit(n) do
    Logger.error("Invalid bit value: #{inspect(n)}. Expected 0 or 1.")
    # Default to OFF
    0b01
  end

  @doc """
  Stops the LED matrix driver GenServer, turning all LEDs off and closing
  the I2C bus.
  """
  def stop(server \\ __MODULE__) do
    GenServer.stop(server, :normal)
  end

  @impl true
  @doc false
  def terminate(_reason, {ref, i2c_address, _mat, _counter, _reflesh_interval}) do
    # Turn all LEDs OFF and close the I2C bus
    stop_led(ref, i2c_address)
    Logger.info("Terminating LED Matrix GenServer")
    :ok
  end

  # The functions below are mainly called directly, outside of the GenServer

  @doc false
  def init_led(bus_name \\ @default_bus_name, i2c_address \\ @default_i2c_address) do
    {:ok, ref} = Circuits.I2C.open(bus_name)
    Circuits.I2C.write(ref, i2c_address, <<@mode1, 0x00>>)
    Circuits.I2C.write(ref, i2c_address, <<@mode2, 0x55>>)
    ref
  end

  @doc false
  def stop_led(ref, i2c_address \\ @default_i2c_address) do
    all_off(ref, i2c_address)
    Circuits.I2C.close(ref)
  end

  @doc false
  def set_xyzw(ref, x, y, z, w, i2c_address \\ @default_i2c_address) do
    Circuits.I2C.write(ref, i2c_address, <<@ledout0, x>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout1, y>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout2, z>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout3, w>>)
  end

  @doc false
  def set_00(ref, i2c_address \\ @default_i2c_address) do
    Circuits.I2C.write(ref, i2c_address, <<@ledout0, 0x51>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout1, 0x55>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout2, 0x51>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout3, 0x55>>)
  end

  @doc false
  def read_led(ref, offset, i2c_address \\ @default_i2c_address) do
    {:ok, data} = Circuits.I2C.write_read(ref, i2c_address, <<@ledout0 + offset>>, 1)

    data
    |> :binary.decode_unsigned()
    |> IO.inspect(label: "Read LED Register #{offset}")
  end

  @doc """
  Turns every LED on the board fully on. Takes a raw I2C `ref` (from
  `Circuits.I2C.open/1` or `init_led/2`), not a GenServer. Useful as a quick
  hardware sanity check.
  """
  def all_on(ref, i2c_address \\ @default_i2c_address) do
    Circuits.I2C.write(ref, i2c_address, <<@ledout0, 0x00>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout1, 0x00>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout2, 0x00>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout3, 0x00>>)
  end

  @doc """
  Turns every LED on the board fully off. Takes a raw I2C `ref` (from
  `Circuits.I2C.open/1` or `init_led/2`), not a GenServer.
  """
  def all_off(ref, i2c_address \\ @default_i2c_address) do
    Circuits.I2C.write(ref, i2c_address, <<@ledout0, 0x55>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout1, 0x55>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout2, 0x00>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout3, 0x00>>)
  end

  @doc false
  def test_start(bus_name \\ @default_bus_name, i2c_address \\ @default_i2c_address) do
    # 1. Open the I2C bus (change to e.g. "i2c-1" to match the environment)
    {:ok, ref} = Circuits.I2C.open(bus_name)

    # 2. Initialize: clear SLEEP (MODE1 register)
    Circuits.I2C.write(ref, i2c_address, <<@mode1, 0x00>>)
    # Circuits.I2C.write(ref, i2c_address, <<@mode2, 0x05>>)

    # 3. Set all LED pins to "PWM control mode" (0-3)
    # 0xAA is binary 10101010 (2 bits per pin, '10' = PWM mode)
    # Enum.each(0..3, fn offset ->
    #   Circuits.I2C.write(ref, i2c_address, <<@pwm0 + offset, 0x55>>)
    # end)
    # This isn't actually done above, so it's unclear whether it's correct.
    test_loop(ref, i2c_address)
  end

  @doc false
  def test_loop(ref, i2c_address \\ @default_i2c_address) do
    Circuits.I2C.write(ref, i2c_address, <<@ledout0, 0x00>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout1, 0x00>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout2, 0x00>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout3, 0x00>>)
    IO.puts("LEDs should be On now.")
    Process.sleep(1000)

    Circuits.I2C.write(ref, i2c_address, <<@ledout0, 0x55>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout1, 0x55>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout2, 0x00>>)
    Circuits.I2C.write(ref, i2c_address, <<@ledout3, 0x00>>)
    IO.puts("LEDs should be Off now.")
    Process.sleep(1000)

    test_loop(ref, i2c_address)
  end
end
