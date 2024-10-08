enum TreeOperation {
  // When the user removes a node(s) into the tree
  delete,
  // When the insert or add a new node into the tree
  insert,
  insertAbove,
  // When the user move a node(s) to another part of the tree
  move,
  // by now this is not used because keyboard ability is not available yet
  paste,
  // When the user override all nodes into the root
  // without using common operations
  replace,
  // When the user clear some CompositeTreeNode
  clearComposite,
  clearRoot,
  // When the user update the internal state of the node
  // Note: should be called always on custom or default implementations
  update,
}
