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
