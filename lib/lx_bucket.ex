defmodule LxBucket do
  defstruct level: +0.0, capacity: 0.0, leak_rate: 1.0, last_drip_time: 0

  @moduledoc """
  Tiny leaky bucket for anomaly detection in a single node.

  This leaky bucket implementation is specifically for detecting anomalies in a single node.
  It has a minimal interface: new/2 and drip_in/1

  new/2 creates a bucket with
  * a given capacity (floa, default 10.0)
  * the leak rate (float, Hz, default 1.0)

  drip_in/1 takes the LxBucket struct returned by new/2 and drips 1.0 unit volume in.
  If the bucket is below capacity, {:ok, new_lx_bucket} is returned.
  If the bucket overflows, {:overflow, new_lx_bucket} is returned.

  Suppose your I2C peripherals are not 100% reliable, not 100% broken, but can devolve
  to 100% broken. You need a way to have your code tolerate some faults and detect when
  to conclude that the peripheral is truly broken, which will generate a visit by a human.
  Maybe the I2C bus is long and subject to EMI. Every failing interaction generates a call to
  LxBucket.drip_in. Your code would probably retry the I2C interaction after a timeout.

  the :overflow return from LxBucket.drip_in/1 can be used to detect anomalies.
  If your application classifies anomalies as faults, it can take whatever recovery
  action is required when the bucket overflows.

  LxBucket is by no means to limited to hardware anomaly detection. LxBuckets could also monitor
  interactions with external software servers. RPC faults could generate a call to LxBucket.drip_in/1,
  with :overflow returns generating a switch to an alternative server for the particular RPC.

  As another example, failed logins could create LxBuckets in a Map that uses the source IP address
  as a key. :overflow returns from LxBucket.drip_in/1 would change the status so that further attempts
  are denied for a certain time. (NB: this is so naive that I caution this is to explain how it could
  be used. If you need industrial-strength security, get software written by someone who has
  sufficient experience to do a good job).

  Another example: suppose you want to detect button pushes by someone who isn't intentionally
  controlling the system, but rather making random button presses. When :overflow is returned, your code
  return the system to the state it had at the beginning of the random button presses.

  If compatible with safety regulations, LxBucket could be incrememnted whenever a new floor button
  in an elevator is pressed. So an immature passenger who presses each floor button would be prevented
  from making the elevator stop at each floor of a 25 story building. The bucket capacity could be set
  to a fraction of the elevator car capacity.

  This use, as well as random pushbotton press recover would require considerable user
  experience engineering.

  LxBucket is a very tiny implmentation with no call backs, no GenServer, no timers -- nothing
  but the LxBucket struct, which contains a float representing the fill level, another
  representing the capacity, and a time representing the time when the bucket fill level was correct.

  At every call to LxBucket/drip_in/1, the leak rate, saved time, and current time are used to calculate
  how much the bucket has drained, and then the drip is added. the new fill level and last drip time are
  updated. If the resulting
  fill level exceeds the capacity, then :overflow is returned, otherwise :ok is returned, along with
  the new LxBucket struct.

  To reduce the probability of clock adjustments producing randome behavior, System.monotonic_time(:millisecond)
  is used in LxBucket.

  N.B. Using LxBucket for admission control is not advised. It would work
  if work that arrives at too high a rate can be discarded. If such work
  must instead  be queued, LxBucket does not suffice. A polling interface,
  with a function such as is_overflowing?/1, could be implmented, but it
  is likely to be more efficient to use a timer-based leaky bucket.
  """

  @doc """
  Create a new LxBucket{} with the same capacity and leak rate as the old bucket
  ## Examples

        iex> old_bucket = (LxBucket.new(50.0, 5.0) |> LxBucket.drip_in!());
        new_bucket = LxBucket.new(old_bucket);
        new_bucket |> dbg;
        new_bucket.level == 0.0;

  """

  # %LxBucket{level: 1.0} = old_bucket

  def new(%LxBucket{capacity: capacity, leak_rate: rate} = _old_bucket)
      when is_float(capacity) and is_float(rate) and capacity > 0.0 and rate > 0,
      do: %LxBucket{
        capacity: capacity,
        leak_rate: rate,
        level: +0.0,
        last_drip_time: System.monotonic_time(:millisecond)
      }

  @doc """
  Create a new LxBucket{} with given capacity and leak rate
  ## Examples

        iex> %LxBucket{capacity: 50.0, leak_rate: 0.5, level: +0.0} = LxBucket.new(50.0, 0.5)

  """

  def new(capacity \\ 10.0, rate \\ 1.0)
      # def new(capacity, rate)
      when is_float(capacity) and is_float(rate) and capacity > 0.0 and rate > 0,
      do: %LxBucket{
        capacity: capacity,
        leak_rate: rate,
        last_drip_time: System.monotonic_time(:millisecond)
      }

  @doc """
  drip volume = 1 into bucket, return {:ok, bucket} or {:overflow, bucket}
  ## Examples

          iex> {:ok, _} = LxBucket.new() |> LxBucket.drip_in()

          iex> {:overflow, _} = (LxBucket.new(1.0) |> LxBucket.drip_in() |> elem(1) |> LxBucket.drip_in())
  """

  def drip_in(%LxBucket{} = bucket) do
    now = System.monotonic_time(:millisecond)
    interval = now - bucket.last_drip_time
    drain_amount = interval / 1000.0 * bucket.leak_rate
    new_level = max(bucket.level - drain_amount + 1.0, 1.0)
    new_bucket = %{bucket | level: new_level, last_drip_time: now}
    {if(new_level <= bucket.capacity, do: :ok, else: :overflow), new_bucket}
  end

  @doc """
  drip volume = 1 into bucket, returns the updated bucket if no overflow
  If the bucket has overflowed, then this raises a RuntimeError with the
  "Leaky Bucket Overflow"
  message
  ## Examples

          iex> %LxBucket{} = LxBucket.new(1.1) |> LxBucket.drip_in!()

          # Raise RuntimeError!

          iex> (LxBucket.new(0.1) |> LxBucket.drip_in!())
  """

  def drip_in!(%LxBucket{} = bucket) do
    {status, new_bucket} = drip_in(bucket)
    if status == :overflow, do: raise("Leaky Bucket Overflow"), else: new_bucket
  end
end
