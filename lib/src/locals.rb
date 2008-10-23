module Pdb
  
  class LocalsNodeNameFormatter < NodeNameFormatter
  end

  class LocalsNodeValueFormatter < NodeValueFormatter
  end

  class LocalsNode < Node
  end

  class LocalsWindow < VariablesWindow
    
    def awakeFromNib()
      super
      $pdb_locals_window = self
    end

    def new_node
      node = LocalsNode.alloc.init
      node.window = self
      node
    end
    
    def prepare_command
      "p locals()"
    end
  end

end