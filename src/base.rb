def make_color(r,g,b,a=1)
  NSColor.colorWithDeviceRed(r, green:g, blue:b, alpha:1)
end

module Pdb

  COLOR_TABLE = [
    [/<function/, make_color(0,0.5,0)],
    [/<module/, make_color(0.5,0.2,0.2)],
    [/<class/, make_color(0,0.5,0.5)],
    [/(object at|instance at)/, make_color(0,0,0.7)],
    [/^\{/, make_color(0,0.4,0.7)],
    [/^\[/, make_color(0.2,0,0.2)],
    [/^(u'|')/, make_color(0.2,0.2,0.6)],
  ]

  $pdb_value_cache = {}

  class NodeNameFormatter < NSFormatter
    def stringForObjectValue(o)
      o.objectForKey("name")
      rescue
      o
    end
  
    def pick_color(value)
      return NSColor.grayColor unless $pdb_connected
      COLOR_TABLE.each do |item|
        return item[1] if value.to_s =~ item[0]
      end
      NSColor.blackColor
    end
  
    def attributedStringForObjectValue(o, withDefaultAttributes:a)
      value = o.objectForKey("value").to_s
      name = o.objectForKey("name").to_s
      font = NSFont.fontWithName("Courier", size:11.0)
      color = pick_color(value)
      keys = [NSFontAttributeName, NSForegroundColorAttributeName]
      objs = [font, color]
      d = NSDictionary.dictionaryWithObjects(objs, forKeys:keys)
      NSAttributedString.alloc.initWithString(name, attributes:d)
      rescue
        nil
    end
  
    def getObjectValue(o, forString:s, errorDescription:err)
      true
    end
  end
  
  class NodeValueFormatter < NSFormatter
    def stringForObjectValue(o)
      value = o.objectForKey("value")
      return value
      rescue
        o
    end
  
    def attributedStringForObjectValue(o, withDefaultAttributes:a)
      value = o.objectForKey("value").to_s
      identifier = o.objectForKey("identifier").to_s
      font = NSFont.fontWithName("Courier", size:11.0)
      color = NSColor.blackColor
      previous_value = $pdb_value_cache[identifier]
      color = NSColor.redColor if value!=previous_value
      color = NSColor.purpleColor if previous_value.nil?
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
  
  class Node
    attr_accessor :value, :name, :is_root, :identifier, :children, :window, :is_editable, :lazy
  
    def init()
      @children = []
      @deleted = []
      @is_root = false
      @name = ''
      @identifier = ''
      @value = '?'
      @is_editable = false
      @lazy = false
      keys = ["name", "value", "identifier"]
      objs = [@name, @value, @identifier]
      @dict = NSMutableDictionary.alloc.initWithObjects(objs, forKeys:keys) 
      self
    end
    
    def dict()
      @dict.setObject(@name, forKey:"name")
      @dict.setObject(@value, forKey:"value")
      @dict.setObject(@identifier, forKey:"identifier")
      @dict
    end
    
    def dict=(d)
      @name = d["name"].to_s
      @identifier = d["identifier"].to_s
      @value = d["value"].to_s
    end
    
    def clear()
      @children = []
    end
  
    def <=>(rs)
      self.name<=>rs.name
    end
  
    def add(node, do_sort = true)
      node.lazy = (node.value.size>0 and (node.value[0].chr=='{' or node.value[0].chr=='['))
      @children<<node
      @children = @children.sort if do_sort
    end
  
    def child_at(index)
      return @children[index]
    end
    
    def remove_child_at(index)
      @deleted << @children[index]
      @children.delete_at(index)
    end
    
    def refresh()
      @window.outlineView.collapseItem(self)
      @window.store_focus()
      prompt = $mound.peek_prompt()
      return 0 unless prompt =~ Pdb::PROMPT
      $mound.enter_exclusive_mode()
      data = $mound.wait_for_content("p #{identifier}", PROMPT, TERMINAL_WAIT_TIMEOUT)
      data = '?' unless data
      @value = data.strip
      $mound.leave_exclusive_mode()
      @window.restore_focus()
    end
    
    def lazy_expand()
      if @children.size==0 and not (@value=="{}" or @value=="[]")
        @window.parse_data(@value).each do |name, value|
          update(name, value)
        end
      end
      #@window.outlineView.reloadItem(self)
      @children.size
    end
  
    def childrenCount()
      return @children.size if @is_root
      return lazy_expand() if @lazy
      @window.store_focus()
      @window.pointer = self
      prompt = $mound.peek_prompt()
      return 0 unless prompt =~ Pdb::PROMPT
      $mound.enter_exclusive_mode()
      data = $mound.wait_for_content("p #{identifier}.__dict__", PROMPT, TERMINAL_WAIT_TIMEOUT)
      @window.process_data(data) if data
      $mound.leave_exclusive_mode()
      @window.restore_focus()
      @children.size
    end
  
    def expandable()
       return false unless value.size>0
       @value[0].chr=='<' and not @value=~/<(type|built-in)/ or @name=='self' or @lazy
    end
  
    def find(name)
      @children.find {|c| c.name==name }
    end
  
    def remember_values()
      $pdb_value_cache[@identifier]=@value
      @children.each {|c| c.remember_values() }
    end
  
    def update(name, value)
      node = find(name)
      if node
        node.value = value
      else
        node = @window.new_node
        node.name = name
        node.value = value
        node.identifier = "#{@identifier}.#{name}" unless @is_root
        node.identifier = name if @is_root
        node.is_editable = @is_root
        add(node)
      end
    end
  end
  
  class OutlineView < NSOutlineView
    attr_accessor :rootWindow
    
    def keyDown(event)
      key_code = event.keyCode
      #NSLog("#{event}")
      if @rootWindow.editable
        firstChar = event.characters.characterAtIndex(0)
        # if the user pressed delete
        if firstChar == NSDeleteFunctionKey || firstChar == NSDeleteCharFunctionKey || firstChar == NSDeleteCharacter
           @rootWindow.delete_row()
           return
        end
        if key_code == 69 # +
          @rootWindow.start_insert()
          return
        end
        if key_code == 36 # ENTER
          @rootWindow.start_edit()
          return
        end
      end
      
      super(event)
    end
    
    
    def _highlightColorForCell(cell)
      NSColor.colorWithCalibratedWhite(0.9, alpha:1.0)
    end
  end
  
  class Window < NSPanel
  
    def init
      super
      self
    end
  
    def awakeFromNib()
    end
  
    def show()
      #.showWindow_(self)
    end
  
    def hide()
      #@windowControllerController.hideWindow_(self)
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
    end
    
    def restore_state()
    end
    
    def prepare_command()
      NSLog("implement prepare_command for #{self}")
    end
    
    def read_content()
      store_state()
      $mound.enter_exclusive_mode()
      data = $mound.wait_for_content(prepare_command(), PROMPT, TERMINAL_WAIT_TIMEOUT)
      #NSLog("got data: #{data}")
      process_data(data) if data
      $mound.leave_exclusive_mode()
      restore_state()
    end
    
  end
  
  class VariablesWindow < Window
    attr_accessor :outlineView, :pointer, :editable, :root
  
    def awakeFromNib()
      super
      @timer = NSTimer.scheduledTimerWithTimeInterval(0.5, target:self, selector:"tick:", userInfo:nil, repeats:true)
      @outlineView.rootWindow = self
      @root = new_node
      @root.is_root = true
      @expanded_identifiers = []
      @pointer = @root
      @editable = false
    end
  
    def new_node
      NSLog("#{self}: implement new_node!")
    end
    
    def init
      super
      self
    end
  
    def outlineViewItemDidExpand(n)
      @expanded_identifiers << n.userInfo["NSObject"].identifier
    end
  
    def outlineViewItemDidCollapse(n)
      @expanded_identifiers.delete n.userInfo["NSObject"].identifier
    end
  
    def outlineView(outlineView, child:index, ofItem:item)
      item ||= @root
      item.child_at(index)
    end
  
    def outlineView(outlineView, isItemExpandable:item) 
      return item.expandable
    end
  
    def outlineView(outlineView, numberOfChildrenOfItem:item)
      item ||= @root
      item.childrenCount()
    end
  
    def outlineView(outlineView, objectValueForTableColumn:tableColumn, byItem:item)
      #NSLog("->#{tableColumn}:#{item} (#{item.name})")
      item.dict
    end
  
    def outlineView(outlineView, setObjectValue:object, forTableColumn:tableColoumn, byItem:item)
      #NSLog("outlineView_setObjectValue_forTableColumn_byItem: #{object}, #{tableColoumn}, #{item}")
      item.dict = object
      item.refresh()
      @outlineView.reloadItem(item, reloadChildren:true)
    end
    
    # def addChild(sender)
    #   selectedRow = @outlineView.selectedRow
    #   if selectedRow < 0
    #     return
    #   end
    #   selectedItem = @outlineView.itemAtRow(selectedRow)
    #   newNode = Node.alloc.init
    #   selectedItem.addChild(newNode)
    #   @outlineView.reloadItem_reloadChildren(@root, true)
    # end
    
    def delete_row()
      selectedRow = @outlineView.selectedRow
      return if selectedRow < 0
      @root.remove_child_at(selectedRow)
      @outlineView.reloadItem(nil, reloadChildren:true)
    end
  
    def parse_data(data)
      result = {}
      return result unless data and data.size>=2
      if data[0].chr=='['
        data = "#{data.strip.chop[1..-1]},"
        index = 0
        pos = 0
        while pos<data.size
          name = index.to_s
          cur = data[pos..pos]
          level = 0
          start = pos
          while (cur!=nil && (cur!=',' || level!=0))
            if cur=='{' || cur=='[' || cur=='('
              level = level + 1
            end
            if cur=='}' || cur==']' || cur==')'
              level = level - 1
            end
            pos = pos + 1
            cur = data[pos..pos]
          end
          value = data[start...pos]
          result[name] = value
          index = index + 1
          pos = pos + 1
        end
      else
        data = "#{data.strip.chop[1..-1]},"
        # really stupid parser of pdb output - quick hack
        while data =~ /'([^']+)': /
          name = $1.strip
          rest = $'
          pos = 0
          cur = rest[pos..pos]
          level = 0
          while (cur!=nil && (cur!=',' || level!=0))
            if cur=='{' || cur=='[' || cur=='('
              level = level + 1
            end
            if cur=='}' || cur==']' || cur==')'
              level = level - 1
            end
            pos = pos + 1
            cur = rest[pos..pos]
          end
          value = rest[0...pos]
          result[name] = value
          data = rest[pos+1..-1]
        end
      end
      result
    end
  
    def process_data(line)
      pairs = parse_data(line)
      @pointer.clear()
      pairs.each do |name, value|
        @pointer.update(name, value)
      end
      if (@pointer===@root)
        @outlineView.reloadItem(nil)
      else
        @outlineView.reloadItem(@pointer)
      end
      @pointer = @root
    end
  
    def find_by_identifier(identifier)
      parts = identifier.split('.')
      node = @root
      while node and parts.size>0
        node = node.find(parts.shift)
      end
      node
    end
  
    def store_scroll_states()
      @saved_scroll = @outlineView.enclosingScrollView.documentVisibleRect.origin
    end
    
    def restore_scroll_states()
      @outlineView.scrollPoint(@saved_scroll)
    end
    
    def store_state()
      super()
      store_focus()
      @root.remember_values()
      store_scroll_states()
    end
  
    def restore_state()
      super()
      @expanded_identifiers = @expanded_identifiers.uniq.sort
      @expanded_identifiers.each do |identifier|
        node = find_by_identifier(identifier)
        @outlineView.expandItem(node) if node
      end
      restore_scroll_states()
      restore_focus()
    end
    
    def refresh()
      @outlineView.reloadItem(@rootNode, reloadChildren:true)
    end
    
    def start_edit()
      selectedRow = @outlineView.selectedRow
      return if selectedRow < 0
      selectedItem = @outlineView.itemAtRow(selectedRow)
      return unless selectedItem.is_editable
      @outlineView.selectRow(selectedRow, byExtendingSelection:false)
      @outlineView.editColumn(0, row:selectedRow, withEvent:nil, select:true)
    end
    
    def start_insert()
      node = new_node()
      node.name = '?'
      node.value = '?'
      node.identifier = '?'
      node.is_editable = true
      @root.add(node, false)
      selectedRow = @root.children.size-1
      @outlineView.reloadItem(@rootNode, reloadChildren:true)
      @outlineView.selectRow(selectedRow, byExtendingSelection:false)
      @outlineView.editColumn(0, row:selectedRow, withEvent:nil, select:true)
    end
  
    def tick(object)
      if @restore_focus
        @restore_focus = false
      
        NSApp.activateIgnoringOtherApps(true) if @was_active_application
        becomeKeyWindow() if @was_key_window
        became_active_application = NSApp.isActive()
        became_key_window = isKeyWindow()
      
        @restore_focus = true if 
          (@was_active_application and not became_active_application) or
          (@was_key_window and not became_key_window)
      end
    end
  end

end