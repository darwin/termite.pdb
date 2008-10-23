class CallstackNodeFormatter < NSFormatter
  
  def stringForObjectValue(o)
      o.objectForKey(key())
    rescue
      o
  end

  def attributedStringForObjectValue(o, withDefaultAttributes:a)
    value = o.objectForKey(key())
    active = CFBooleanGetValue(o.objectForKey("active"))
    render_bold = active && $pdb_connected
    font = NSFont.fontWithName("Courier Bold", size:11.0) if render_bold
    font = NSFont.fontWithName("Courier", size:11.0) unless render_bold
    color = NSColor.blackColor
    color = NSColor.blueColor if active
    color = NSColor.grayColor unless $pdb_connected
    keys = [NSFontAttributeName, NSForegroundColorAttributeName]
    objs = [font, color]
    d = NSDictionary.dictionaryWithObjects(objs, forKeys:keys)
    NSAttributedString.alloc.initWithString(value, attributes:d)
    rescue
      nil
  end

  def getObjectValue(o, forString:s, errorDescription:err)
    true
  end
end

class CallstackNodeFileFormatter < CallstackNodeFormatter
  def key
    "file"
  end
end

class CallstackNodeMethodFormatter < CallstackNodeFormatter
  def key
    "method"
  end
end

class CallstackNodeLineFormatter < CallstackNodeFormatter
  def key
    "line"
  end
end

class CallstackNodePathFormatter < CallstackNodeFormatter
  def key
    "path"
  end
end

class TableView < NSTableView
  attr_accessor :rootWindow
  
  def keyDown(event)
    key_code = event.keyCode
    if key_code == 36 # ENTER
      @rootWindow.switch_frame()
      return
    end
    super(event)
  end
  
  def _highlightColorForCell(cell)
    NSColor.colorWithCalibratedWhite(0.9, alpha:1.0)
  end

end

class CallstackWindow < Window
  attr_accessor :tableView

  def awakeFromNib()
    @timer = NSTimer.scheduledTimerWithTimeInterval(0.5, target:self, selector:'tick:', userInfo:nil, repeats:true)
    $pdb_callstack_window = self
    @tableView.rootWindow = self
    @tableView.setDoubleAction(:switch_frame)
    @tableView.setTarget(self)
  end
  
  def init
    super
    @list = []
    self
  end
  
  def find_active_frame()
    index = 0
    while index<@list.size
      return index if @list[index]["active"]
      index = index + 1
    end
    -1
  end
  
  def create_row(file, method, line, path, active)
    keys = ["file", "method", "line", "path", "active"]
    objs = [file, method, line, path, active]
    NSMutableDictionary.alloc.initWithObjects(objs, forKeys:keys) 
  end
  
  def numberOfRowsInTableView(tableView)
    return 0 unless @list
    @list.size
  end
  
  def tableView(tableView, objectValueForTableColumn:column, row:rowIndex)
    @list[rowIndex]
  end
  
  def tableView(tableView, setObjectValue:object, forTableColumn:column, row:rowIndex)
    @list[rowIndex] = object
  end
  
  def switch_frame()
    new_frame = @tableView.selectedRow()
    current_frame = find_active_frame()
    NSLog("#{current_frame}")
    return if current_frame==-1
    
    shift = current_frame - new_frame
    return if shift == 0
    if shift>0 then command = "down" else command = "up" end

    store_state()
    $mound.enter_exclusive_mode()
    shift.abs.times { $mound.wait_for_content(command, Pdb::PROMPT, Pdb::TERMINAL_WAIT_TIMEOUT) }
    $mound.leave_exclusive_mode()
    
    $pdb_value_cache = {} #TODO: better
    windows = [$pdb_watches_window, $pdb_locals_window, $pdb_globals_window]
    windows.each {|w| w.read_content()}
    
    @list[current_frame].setObject(false, forKey:"active")
    @list[new_frame].setObject(true, forKey:"active")
    
    refresh()
    restore_state()
  end
  
  def store_scroll_states()
    @saved_scroll = @tableView.enclosingScrollView.documentVisibleRect.origin
  end
  
  def restore_scroll_states()
    @tableView.scrollPoint(@saved_scroll)
  end
  
  def store_focus()
    @was_active_application = NSApp.isActive()
    @was_key_window = isKeyWindow()
  end

  def restore_focus()
    # here we need to restore focus asynchronously after some time
    # for example TextMate may activate and we want to steal focus after then
    @restore_focus = true
  end
  
  def store_state()
    store_focus()
    store_scroll_states()
  end

  def restore_state()
    restore_scroll_states()
    restore_focus()
  end
  
  def prepare_command()
    "w"
  end
  
  def read_content()
    store_state()
    $mound.enter_exclusive_mode()
    data = $mound.wait_for_content(prepare_command(), Pdb::PROMPT, Pdb::TERMINAL_WAIT_TIMEOUT)
    #NSLog("got data: #{data}")
    process_data(data) if data
    $mound.leave_exclusive_mode()
    restore_state()
  end
  
  def refresh()
    @tableView.reloadData()
  end
  
  def parse_data(data)
    result = []
    return result unless data
    lines = data.split("\n")
    index = 0
    while (index<lines.size)
      line = lines[index]
      if line =~ /^(.*)\/(.*?)\((\d+)\)(.*)$/
        path = $1.strip
        active = false
        if path[0].chr == '>'
          active = true
          path = path[2..-1] 
        end
        result << create_row($2, $4, $3, path, active)
      else
        result << create_row('?', '', '', '', false)
      end
      index = index + 2
    end
    result.reverse
  end

  def process_data(line)
    @list = parse_data(line)
    refresh()
  end

  def tick(object)
    if @restore_focus
      @restore_focus = false
    
      NSApp.activateIgnoringOtherApps(true) if @was_active_application
      becomeKeyWindow() if @was_key_window
      became_active_application = NSApp.isActive()
      became_key_window = isKeyWindow()
    
      @restore_focus = true if 
        (@was_key_windowtive_application and not became_active_application) or
        (@was_key_window and not became_key_window)
    end
  end

end
