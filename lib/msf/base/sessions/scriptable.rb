# -*- coding: binary -*-

module Msf::Session

module Scriptable

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    #
    # If the +script+ exists, return its path. Otherwise return nil
    #
    def find_script_path(script)
      # Find the full file path of the specified argument
      check_paths =
        [
          script,
          ::File.join(script_base, "#{script}"),
          ::File.join(script_base, "#{script}.rb"),
          ::File.join(user_script_base, "#{script}"),
          ::File.join(user_script_base, "#{script}.rb")
        ]

      full_path = nil

      # Scan all of the path combinations
      check_paths.each { |path|
        if ::File.exists?(path)
          full_path = path
          break
        end
      }

      full_path
    end
    def script_base
      ::File.join(Msf::Config.script_directory, self.type)
    end
    def user_script_base
      ::File.join(Msf::Config.user_script_directory, self.type)
    end

  end

  #
  # Override
  #
  def execute_file
    raise NotImplementedError
  end

  #
  # Executes the supplied script, Post module, or local Exploit module with
  #   arguments +args+
  #
  # Will search the script path.
  #
  def execute_script(script_name, *args)
    mod = framework.modules.create(script_name)
    if mod
      # Don't report module run events here as it will be taken care of
      # in +Post.run_simple+
      opts = { 'SESSION' => self.sid }
      args.each do |arg|
        k,v = arg.split("=", 2)
        opts[k] = v
      end
      if mod.type == "post"
        mod.run_simple(
          # Run with whatever the default stance is for now.  At some
          # point in the future, we'll probably want a way to force a
          # module to run in the background
          #'RunAsJob' => true,
          'LocalInput'  => self.user_input,
          'LocalOutput' => self.user_output,
          'Options'     => opts
        )
      elsif mod.type == "exploit"
        # well it must be a local, we're not currently supporting anything else
        if mod.exploit_type == "local"
          # get a copy of the session exploit's datastore if we can
          original_exploit_datastore = self.exploit.datastore || {}
          copy_of_orig_exploit_datastore = original_exploit_datastore.clone
          # we don't want to inherit a couple things, like AutoRunScript's
          to_neuter = %w{AutoRunScript InitialAutoRunScript LPORT TARGET}
          to_neuter.each do |setting|
            copy_of_orig_exploit_datastore.delete(setting)
          end

          # merge in any opts that were passed in, defaulting all other settings
          # to the values from the datastore (of the exploit) that spawned the
          # session
          local_exploit_opts = copy_of_orig_exploit_datastore.merge(opts)

          # try to run this local exploit, which is likely to be exception prone
          begin
            new_session = mod.exploit_simple(
              'Payload'       => local_exploit_opts['PAYLOAD'],
              'Target'       => local_exploit_opts['TARGET'],
              'LocalInput'    => self.user_input,
              'LocalOutput'   => self.user_output,
              'Options'       => local_exploit_opts
              )
          rescue ::Interrupt
            raise $!
          rescue ::Exception => e
            print_error("Local exploit exception (#{mod.refname}): " +
                        "#{e.class} #{e}")
            if(e.class.to_s != 'Msf::OptionValidateError')
              print_error("Call stack:")
              e.backtrace.each do |line|
                break if line =~ /lib.msf.base.simple/
                print_error("  #{line}")
              end
            end
          end # end rescue

        end # end if local
      end # end if exploit

    else
      full_path = self.class.find_script_path(script_name)

      # No path found?  Weak.
      if full_path.nil?
        print_error("The specified script could not be found: #{script_name}")
        return true
      end
      framework.events.on_session_script_run(self, full_path)
      execute_file(full_path, args)
    end
  end

end

end
