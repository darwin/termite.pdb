module Pdb
  
  class WatchesNodeNameFormatter < NodeNameFormatter
    def getObjectValue(o, forString:s, errorDescription:err)
      #NSLog("getObjectValue_forString_errorDescription: #{o}, #{s}, #{err}")
      keys = ["name", "value", "identifier"]
      objs = [s, '?', s]
      dict = NSMutableDictionary.alloc.initWithObjects(objs, forKeys:keys)
      o.assign(dict)
      true
    end
  end

  class WatchesNodeValueFormatter < NodeValueFormatter
  end

  class WatchesNode < Node
  end

  class WatchesWindow < VariablesWindow
    
    def awakeFromNib()
      super()
      @editable = true
      $pdb_watches_window = self
    end
    
    def new_node
      node = WatchesNode.alloc.init
      node.window = self
      node
    end

    def outlineView(outlineView, shouldEditTableColumn:col, item:item)
      item.is_editable
    end
    
    def read_content()
      store_state()
      $mound.enter_exclusive_mode()
      @stored_items.each do |item|
        data = $mound.wait_for_content(item, PROMPT, TERMINAL_WAIT_TIMEOUT)
        @root.update(item, data)
      end
      $mound.leave_exclusive_mode()
      refresh()
      restore_state()
    end
    
    def store_state()
      super()
      @stored_items =  @root.children.collect {|node| node.identifier }
    end
    
    def restore_state()
      super()
    end
  end
end