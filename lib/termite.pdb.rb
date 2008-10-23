require 'src/base.rb'
require 'src/locals.rb'
require 'src/globals.rb'
require 'src/watches.rb'
require 'src/callstack.rb'

module Pdb
  PROMPT = /^\(Pdb\)/
  TERMINAL_WAIT_TIMEOUT = 2.0

  class Watcher < TermiteAPI::Watcher
    
    def reset()
      @windows = [$pdb_watches_window, $pdb_locals_window, $pdb_globals_window, $pdb_callstack_window]
      @state = 'waiting'
    end
    
    def watch(line)
      NSLog("watch[#{@state}]: '#{line}'")
      case @state
      when 'waiting'
        unless line.match(PROMPT)
          $pdb_connected = false
          @windows.each {|w| w.refresh()}
          return
        end
        $pdb_connected = true
        $pdb_value_cache = {} #TODO: better
        @windows.each {|w| w.read_content()}
        false
      end
    end
  end

  class Controller < NSWindowController
    def init()
      super
      pdb_nib_path = File.join(File.dirname(__FILE__), 'res', 'pdb.nib')
      load_nib(pdb_nib_path, self)
    end
  end

  watcher = Watcher.alloc.init
  $mound.watchers << watcher
  controller = Controller.alloc.init
end