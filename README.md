# PCA9622Matrix8x8

Elixir/Nerves driver for the switch-science
["I2C 8x8 LEDマトリックス基板" (I2C 8x8 LED matrix board)](https://www.switch-science.com/products/2071)
board, which drives an 8x8 LED matrix over I2C using the
[PCA9622](http://doc.switch-science.com/schematic/PCA9622_aki_matrix/PCA9622_aki_matrix_sch.pdf)
constant-current LED driver in a row/column multiplexed configuration.

Target machine: [BeagleBone Green](https://www.beagleboard.org/boards/seeedstudio-beaglebone-green).

Includes `PCA9622Matrix8x8.CharGen`, a small character generator that
renders decimal digits (0-9) and, given a radix of 16, hexadecimal digits
(A-F) as 8x8 bitmaps suitable for `PCA9622Matrix8x8.set_matrix/1`.

## Installation

The package can be installed by adding `pca9622matrix8x8` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pca9622matrix8x8, "~> 0.2.0"}
  ]
end
```

## Usage

```elixir
# Start the matrix driver (a GenServer) under your supervision tree.
PCA9622Matrix8x8.start_link()

# Show a hexadecimal digit (e.g. "F").
PCA9622Matrix8x8.CharGen.digit_strlist(15, 16)
|> PCA9622Matrix8x8.CharGen.strlist_tuples()
|> PCA9622Matrix8x8.set_matrix()
```

`start_link/1` takes an options keyword list, so multiple boards can be
driven independently:

```elixir
PCA9622Matrix8x8.start_link(
  bus_name: "i2c-1",
  i2c_address: 0x52,
  name: :second_matrix
)

PCA9622Matrix8x8.set_matrix(:second_matrix, mat)
```

Pass `name: nil` to start an unnamed process and address it by pid instead.

`:reflesh_interval` defaults to `0` (refresh as fast as possible). It mainly
exists to slow the column scan down so you can observe the dynamic lighting;
a nonzero value causes visible flicker.

Pass `:priority` (`:high`, `:normal` or `:low`) to set the GenServer
process's scheduling priority, e.g. `priority: :high` to help keep the
column scan timely under system load.

Pass `:orientation` to choose which side of the board the top of the image
faces: `:north_up` (default), `:west_up`, `:east_up` or `:south_up`. It can
also be changed at runtime:

```elixir
PCA9622Matrix8x8.start_link(orientation: :west_up)
PCA9622Matrix8x8.set_orientation(:south_up)
```

See `PCA9622Matrix8x8.Demo` for a complete example that counts up once a
second and displays the current number.

Documentation is generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm) at
<https://hexdocs.pm/pca9622matrix8x8>.
