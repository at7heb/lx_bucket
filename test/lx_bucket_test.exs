defmodule LxBucketTest do
  use ExUnit.Case
  doctest LxBucket

  test "can create leaky bucket" do
    assert %LxBucket{leak_rate: 1.0, capacity: 10.0, level: +0.0} = LxBucket.new()
  end

  test "can drip in without overflowing" do
    b = LxBucket.new()

    {result, _bucket} =
      Enum.reduce(1..9, {:unk, b}, fn _index, {_status, bucket} -> LxBucket.drip_in(bucket) end)

    assert result == :ok
  end

  test "can drip in and overflow" do
    b = LxBucket.new()

    {result, _bucket} =
      Enum.reduce(1..11, {:unk, b}, fn _index, {_status, bucket} -> LxBucket.drip_in(bucket) end)

    refute result == :ok
  end

  test "bucket doesn't overflow" do
    b = LxBucket.new()

    {result, _bucket} =
      Enum.reduce(1..10, {:unk, b}, fn _index, {_status, bucket} -> LxBucket.drip_in(bucket) end)

    assert result == :ok
  end

  test "bucket drains" do
    b = LxBucket.new()

    {result, bucket} =
      Enum.reduce(1..10, {:unk, b}, fn _index, {_status, bucket} -> LxBucket.drip_in(bucket) end)

    assert result == :ok
    # 5 seconds
    Process.sleep(5000)
    {:ok, bucket} = LxBucket.drip_in(bucket)
    assert bucket.level > 5.9 and bucket.level < 6.1
  end

  test "bucket drains with millisecond resolution" do
    b = LxBucket.new(10.0, 1000.0)

    {result, bucket} =
      Enum.reduce(1..10, {:unk, b}, fn _index, {_status, bucket} -> LxBucket.drip_in(bucket) end)

    assert result == :ok
    # 5 seconds
    Process.sleep(5)
    {:ok, bucket} = LxBucket.drip_in(bucket)
    assert bucket.level > 3.9
    assert bucket.level < 5.1
  end

  test "performance; never fails" do
    # b = LxBucket.new()
    # Benchee.run(%{success: fn -> LxBucket.drip_in(b) end})

    # {:overflow, b} =
    #   Enum.reduce(1..11, {:unk, b}, fn _index, {_status, bucket} -> LxBucket.drip_in(bucket) end)

    # Benchee.run(%{overflow: fn -> LxBucket.drip_in(b) end})
    # # ensure success
    assert 1 == 1
  end

  test "create leaky bucket from an old one" do
    old_bucket = LxBucket.new(50.0, 5.0) |> LxBucket.drip_in!()
    new_bucket = LxBucket.new(old_bucket)
    assert new_bucket.level == 0.0
    assert old_bucket.level > 0.0
  end
end
