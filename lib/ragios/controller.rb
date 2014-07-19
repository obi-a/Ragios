module Ragios
  class Controller
    #see contracts: https://github.com/egonSchiele/contracts.ruby
    include Contracts
    #types
    Monitor = Hash
    Monitor_id = String

    def self.scheduler
      @scheduler ||= Ragios::Scheduler.new(self)
    end
    def self.model
      @model ||= Ragios::Database::Model.new(Ragios::CouchdbAdmin.get_database)
    end

    Contract Monitor_id => Bool
    def self.stop(monitor_id)
      scheduler.unschedule(monitor_id)
      !!model.update(monitor_id, status_: "stopped")
    rescue Leanback::CouchdbException => e
      handle_error(monitor_id, e)
    end

    Contract Monitor_id => Bool
    def self.delete(monitor_id)
      monitor = model.find(monitor_id)
      scheduler.unschedule(monitor_id) if is_active?(monitor)
      !!model.delete(monitor_id)
    rescue Leanback::CouchdbException => e
      handle_error(monitor_id, e)
    end

    Contract Monitor_id, Hash => Bool
    def self.update(monitor_id, options)
      message = "Cannot edit system settings"
      unless options.keys.to_set.disjoint? [:type, :status_, :created_at_, :creation_timestamp_].to_set
        raise Ragios::CannotEditSystemSettings.new(error: message), message
      end
      model.update(monitor_id, options)
      monitor = model.find(monitor_id)
      if is_active?(monitor)
        scheduler.unschedule(monitor_id)
        add_to_scheduler(generic_monitor(monitor))
      end
      true
    rescue Leanback::CouchdbException => e
      handle_error(monitor_id, e)
    end

    def self.get(monitor_id)
      model.find(monitor_id)
    end
    def self.get_all
      model.all_monitors
    end

    Contract Monitor_id => Bool
    def self.restart(monitor_id)
      monitor = model.find(monitor_id)
      return true if is_active?(monitor)
      add_to_scheduler(generic_monitor(monitor))
      !!model.update(monitor_id, status_: "active")
    rescue Leanback::CouchdbException => e
      handle_error(monitor_id, e)
    end
    def self.test_now(monitor_id)
      monitor = model.find(monitor_id)
      perform(generic_monitor(monitor))
    end

    def self.where(options)
      model.monitors_where(options)
    end

    def self.restart_all
      monitors = model.active_monitors
      unless monitors.empty?
        monitors.each do |monitor|
          add_to_scheduler(generic_monitor(monitor))
        end
      end
    end

    def self.get_current_state(monitor_id)
      model.get_monitor_state(monitor_id)
    end

    Contract Hash => Monitor
    def self.add(monitor)
      monitor_with_id = monitor.merge({created_at_: Time.now, status_: 'active', _id: unique_id})
      this_generic_monitor = generic_monitor(monitor_with_id)
      add_to_scheduler(this_generic_monitor)
      model.save(this_generic_monitor.id, this_generic_monitor.options)
      return this_generic_monitor.options
    end
    def self.perform(this_generic_monitor)
      this_generic_monitor.test_command?
      log_results(this_generic_monitor)
    end
    def self.failed(monitor, test_result)
      save_notification("failed", monitor, test_result)
    end
    def self.resolved(monitor, test_result)
      save_notification("resolved", monitor, test_result)
    end

  private
    def self.handle_error(monitor_id, e)
      if e.response[:error] == "not_found"
        raise Ragios::MonitorNotFound.new(error: "No monitor found"), "No monitor found with id = #{monitor_id}"
      else
        raise e
      end
    end
    def self.save_notification(event, monitor, test_result)
      model.save(unique_id,
        monitor_id: monitor[:_id],
        monitor: monitor,
        test_result: test_result,
        type: "notification",
        notifier: monitor[:via],
        tag: monitor[:tag],
        event: event)
    end
    def self.unique_id
      UUIDTools::UUID.random_create.to_s
    end
    def self.log_results(this_generic_monitor)
      test_result = {
        monitor_id: this_generic_monitor.id,
        state: this_generic_monitor.state,
        test_result: this_generic_monitor.test_result,
        time_of_test: this_generic_monitor.time_of_test,
        timestamp_of_test: this_generic_monitor.timestamp_of_test,
        monitor: this_generic_monitor.options,
        tag: this_generic_monitor.options[:tag],
        type: "test_result"
      }
      model.save(unique_id, test_result)
    end
    def self.generic_monitor(monitor)
      GenericMonitor.new(monitor)
    end
    def self.is_active?(monitor)
      monitor[:status_] == "active"
    end
    def self.add_to_scheduler(generic_monitor)
      args = {time_interval: generic_monitor.options[:every],
                tags: generic_monitor.id,
                object: generic_monitor }
      scheduler.schedule(args)
    end
  end
end
