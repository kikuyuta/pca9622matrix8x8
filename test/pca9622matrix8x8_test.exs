defmodule PCA9622Matrix8x8.CharGenTest do
  use ExUnit.Case, async: true

  alias PCA9622Matrix8x8.CharGen

  test "digit_strlist/1 returns 8 rows of 8 characters for decimal digits" do
    for n <- 0..9 do
      rows = CharGen.digit_strlist(n)
      assert length(rows) == 8
      assert Enum.all?(rows, &(String.length(&1) == 8))
    end
  end

  test "digit_strlist/2 supports hexadecimal digits A-F" do
    for n <- 10..15 do
      rows = CharGen.digit_strlist(n, 16)
      assert length(rows) == 8
      assert Enum.all?(rows, &(String.length(&1) == 8))
    end
  end

  test "strlist_tuples/1 converts row strings into a tuple of bit tuples" do
    result = CharGen.digit_strlist(0) |> CharGen.strlist_tuples()
    assert tuple_size(result) == 8
    assert elem(result, 0) == {0, 0, 0, 0, 0, 0, 0, 0}
  end
end

defmodule PCA9622Matrix8x8Test do
  use ExUnit.Case, async: true

  # Matrix with a single pixel lit at (x, y) = (1, 0), i.e. row 0, column 1
  defp single_pixel(x, y) do
    PCA9622Matrix8x8.set_matrix_all(0)
    |> then(&put_elem(&1, y, put_elem(elem(&1, y), x, 1)))
  end

  test "rotate_matrix/2 with :west_up is the identity" do
    mat = single_pixel(1, 0)
    assert PCA9622Matrix8x8.rotate_matrix(mat, :west_up) == mat
  end

  test "rotate_matrix/2 rotates clockwise, 180 and counter-clockwise" do
    mat = single_pixel(1, 0)
    assert PCA9622Matrix8x8.rotate_matrix(mat, :north_up) == single_pixel(7, 1)
    assert PCA9622Matrix8x8.rotate_matrix(mat, :east_up) == single_pixel(6, 7)
    assert PCA9622Matrix8x8.rotate_matrix(mat, :south_up) == single_pixel(0, 6)
  end

  test "four clockwise rotations return the original matrix" do
    mat = PCA9622Matrix8x8.CharGen.digit_strlist(7) |> PCA9622Matrix8x8.CharGen.strlist_tuples()

    assert Enum.reduce(1..4, mat, fn _, m -> PCA9622Matrix8x8.rotate_matrix(m, :north_up) end) ==
             mat
  end
end
