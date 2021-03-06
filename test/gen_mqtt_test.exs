defmodule GenMQTTTest do
  use ExUnit.Case

  defmodule IntegrationTest do
    use GenMQTT

    def start_link(pid, opts \\ []) do
      GenMQTT.start_link(__MODULE__, pid, opts)
    end

    def on_connect(state) do
      send state, :connected
      {:ok, state}
    end

    def on_disconnect(state) do
      send state, :disconnected
      {:ok, state}
    end

    def on_publish(topic, message, state) do
      send state, {:published, self, topic, message}
      {:ok, state}
    end

    def on_subscribe(subscription, state) do
      send state, {:subscribed, subscription}
      {:ok, state}
    end

    def on_unsubscribe(subscription, state) do
      send state, {:unsubscribed, subscription}
      {:ok, state}
    end

    def terminate(:normal, state) do
      send state, :shutdown
      :ok
    end
    def terminate(_reason, _state) do
      :ok
    end
  end

  test "should be able to link a process" do
    assert {:ok, _pid} = IntegrationTest.start_link(self)
  end

  test "should return already started if a named process has been started" do
    assert {:ok, pid} = IntegrationTest.start_link(self, name: MyTestName)
    assert {:error, {:already_started, ^pid}} = IntegrationTest.start_link(self, name: MyTestName)
  end

  test "should be able to connect" do
    {:ok, _pid} = IntegrationTest.start_link(self)
    assert_receive :connected
  end

  test "subscribe and then publish" do
    {:ok, pid} = IntegrationTest.start_link(self)
    assert_receive :connected

    assert :ok = GenMQTT.subscribe(pid, "foo", 0)
    assert_receive {:subscribed, [{"foo", 0}]}

    assert :ok = GenMQTT.publish(pid, "foo", "foo bar baz!", 0)
    assert_receive {:published, ^pid, ["foo"], "foo bar baz!"}
  end

  test "subscribe and then unsubscribe" do
    {:ok, pid} = IntegrationTest.start_link(self)
    assert_receive :connected

    assert :ok = GenMQTT.subscribe(pid, "foo", 0)
    assert_receive {:subscribed, [{"foo", 0}]}

    assert :ok = GenMQTT.unsubscribe(pid, "foo")
    assert_receive {:unsubscribed, [["foo"]]}
  end

  test "subscribe and then unsubscribe to multiple topics" do
    {:ok, pid} = IntegrationTest.start_link(self)
    assert_receive :connected

    assert :ok = GenMQTT.subscribe(pid, [{"foo", 0}, {"bar", 1}])
    assert_receive {:subscribed, [{"foo", 0}, {"bar", 1}]}

    assert :ok = GenMQTT.unsubscribe(pid, "bar")
    assert_receive {:unsubscribed, [["bar"]]}

    assert :ok = GenMQTT.unsubscribe(pid, "foo")
    assert_receive {:unsubscribed, [["foo"]]}
  end

  test "publish and receive" do
    {:ok, pid1} = IntegrationTest.start_link(self, client: "one")
    assert_receive :connected
    {:ok, pid2} = IntegrationTest.start_link(self, client: "two")
    assert_receive :connected

    # subscribe to a topic on one
    assert :ok = GenMQTT.subscribe(pid1, "foo", 0)
    assert_receive {:subscribed, [{"foo", 0}]}
    assert :ok = GenMQTT.publish(pid2, "foo", "bar", 0)
    # subscribing pid (pid1) should receive the message from
    # the sender (pid2)
    assert_receive {:published, ^pid1, ["foo"], "bar"}
  end

  test "connect and then disconnect" do
    {:ok, pid} = IntegrationTest.start_link(self, client: "three")
    assert_receive :connected
    assert :ok = GenMQTT.disconnect(pid)
    assert_receive :shutdown
  end

  test "using info_fun" do
    parent = self
    opts =
      [client: "four",
       info_fun: {
       fn({event, _message_id}, state) ->
         send parent, event
         [event|state]
       end, []}]

    {:ok, pid} = IntegrationTest.start_link(self, opts)
    assert_receive :connack_in
    assert_receive :connected
    assert :ok = GenMQTT.disconnect(pid)
    assert_receive :connect_out
    assert_receive :shutdown
  end

  defmodule ModuleWithOptions do
    use GenMQTT

    def start_link(opts) do
      GenMQTT.start_link(__MODULE__, :na, opts)
    end

    def start(opts) do
      GenMQTT.start(__MODULE__, :na, opts)
    end
  end

  test "init with username but with no password should raise" do
    assert_raise ArgumentError, fn ->
      ModuleWithOptions.start_link username: "foo"
    end
    assert_raise ArgumentError, fn ->
      ModuleWithOptions.start username: "foo"
    end
  end

  test "init with password but with no user name should raise" do
    assert_raise ArgumentError, fn ->
      ModuleWithOptions.start_link password: "foo"
    end
    assert_raise ArgumentError, fn ->
      ModuleWithOptions.start password: "foo"
    end
  end

  test "register a process using a third-party process registry" do
    :ok = Application.ensure_started(:gproc)
    name = {:n, :l, :test}
    process_name = {:via, :gproc, name}

    {:ok, pid} = ModuleWithOptions.start_link(name: process_name)
    assert {^pid, :undefined} = :gproc.await(name, 1000)
  end
end
