#--
# This file is part of Sonic Pi: http://sonic-pi.net
# Full project source: https://github.com/samaaron/sonic-pi
# License: https://github.com/samaaron/sonic-pi/blob/master/LICENSE.md
#
# Copyright 2013, 2014 by Sam Aaron (http://sam.aaron.name).
# All rights reserved.
#
# Permission is granted for use, copying, modification, distribution,
# and distribution of modified versions of this work as long as this
# notice is included.
#++
module SonicPi
  class Node
    attr_reader :id, :comms

    NODE_HANDLER_SEM = Mutex.new

    def initialize(id, comms, arg_validation_fn = nil)
      @id = id
      @comms = comms
      @state = :pending
      @state_change_sem = Mutex.new
      @on_destroyed_callbacks = []
      @on_started_callbacks = []
      @arg_validation_fn = arg_validation_fn

      killed_event_id = @comms.event_gensym("/sonicpi/node/killed#{id}")
      paused_event_id = @comms.event_gensym("/sonicpi/node/paused#{id}")
      started_event_id = @comms.event_gensym("/sonicpi/node/started#{id}")
      created_event_id = @comms.event_gensym("/sonicpi/node/created#{id}")

      @comms.add_event_handler("/n_end", killed_event_id) do |payload|
        if(id.to_i == payload[0].to_i)
          @state_change_sem.synchronize do
            prev_state = @state
            @state = :destroyed
            call_on_destroyed_callbacks if prev_state != :destroyed

          end
          [:remove_handlers,
            [ ["/n_go", created_event_id],
              ["/n_off", paused_event_id],
              ["/n_on", started_event_id],
              ["/n_end", killed_event_id]]]
        end
      end

      @comms.add_event_handler("/n_off", paused_event_id) do |payload|
        if(id.to_i == payload[0].to_i)
          @state_change_sem.synchronize do
            @state = :paused
          end
        end
      end

      @comms.add_event_handler("/n_on", started_event_id) do |payload|
        if(id.to_i == payload[0].to_i)
          @state_change_sem.synchronize do
            @state = :running
          end
        end
      end

      @comms.add_event_handler("/n_go", created_event_id) do |payload|
        if(id.to_i == payload[0].to_i)
          @state_change_sem.synchronize do
            prev_state = @state
            @state = :running
            call_on_started_callbacks if prev_state == :pending
          end
        end
      end
    end

    # block will be called when the node is destroyed or immediately if
    # node is already destroyed. Possibly executed on a separate thread.
    def on_destroyed(&block)
      @state_change_sem.synchronize do
        if @state == :destroyed
          block.call
        else
          @on_destroyed_callbacks << block
        end
      end
    end

    def on_started(&block)
      @state_change_sem.synchronize do
        if @state != :pending
          block.call
        else
          @on_started_callbacks << block
        end
      end
    end

    def kill(now=false)
      @comms.kill_node @id, now
      self
    end

    def pause(now=false)
      @comms.node_pause @id, now
      self
    end

    def run(now=false)
      @comms.node_run @id, now
      self
    end

    def ctl(*args)
      args = resolve_synth_opts_hash_or_array(args)
      args = @arg_validation_fn.call(args) if @arg_validation_fn
      @comms.node_ctl @id, args
      self
    end

    def control(*args)
      ctl(*args)
    end

    def live?
      !(@state == :destroyed)
    end

    def destroyed?
      @state == :destroyed
    end

    def paused?
      @state == :paused
    end

    def running?
      @state == :running
    end

    def state
      @state
    end

    def to_i
      @id.to_i
    end

    def to_f
      @id.to_f
    end

    def to_s
      "#<SonicPi::Node @id=#{@id}>"
    end

    def inspect
      to_s
    end

    def blank_node?
      false
    end

    private

    def call_on_destroyed_callbacks
      @on_destroyed_callbacks.each{|cb| cb.call}
      @on_destroyed_callbacks = []
    end

    def call_on_started_callbacks
      @on_started_callbacks.each{|cb| cb.call}
      @on_started_callbacks = []
    end
  end
end
