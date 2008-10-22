module Pdb
  
  class GlobalsNodeNameFormatter < NodeNameFormatter
  end

  class GlobalsNodeValueFormatter < NodeValueFormatter
  end

  class GlobalsNode < Node
  end

  class GlobalsWindow < VariablesWindow
    
    def awakeFromNib()
      super
      $pdb_globals_window = self
    end

    def new_node
      node = GlobalsNode.alloc.init
      node.window = self
      node
    end
    
    def prepare_command
      "p globals()"
    end

  end

end