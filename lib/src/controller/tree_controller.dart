import 'package:flutter_tree_view/src/entities/enums/move_to_position.dart';

import '../entities/enums/log_level.dart';
import '../entities/node/node.dart';
import '../entities/tree/tree_operation.dart';
import '../entities/tree_node/composite_tree_node.dart';
import '../entities/tree_node/leaf_tree_node.dart';
import '../entities/tree_node/tree_node.dart';
import '../exceptions/invalid_node_update.dart';
import '../exceptions/invalid_type_ref.dart';
import '../exceptions/node_not_exist_in_tree.dart';
import 'base/base_tree_controller.dart';

/// The [`TreeController`] manages a tree of nodes, allowing for the manipulation and querying of its structure.
/// This includes the `insertion`, `deletion`, `updating`, and `movement` of nodes within the tree.
/// Additionally, it supports operations on node selections and notifies subscribers when there are changes in the tree.
class TreeController extends BaseTreeController {
  TreeController(String rootId, List<TreeNode> nodes) {
    root = root.copyWith(children: [...nodes]);
    setNewIdToRoot(rootId);
  }

  void setNewIdToRoot(String id) {
    verifyState();
    assert(id.isNotEmpty, 'The id passed cannot be empty');
    assert(id.replaceAll(RegExp(r'\p{Z}', unicode: true), '').isNotEmpty, 'The id passed cannot be empty');
    final lastNodeState = root.node;
    final newRootState = root.clone();
    newRootState.updateInternalNodesByParentId(id);
    root.addNewChange([...newRootState.children], TreeOperation.update, lastNodeState);
    root = root.copyWith(
      node: root.node.copyWith(
        id: id,
      ),
    );
    root.updateInternalNodesByParentId(id);
    notifyListeners();
  }

  @override
  void insertAt(TreeNode node, String nodeTargetId, {bool removeIfNeeded = false}) {
    logger.writeLog(
      level: LogLevel.info,
      message: 'Should insert the node type ${node.runtimeType}(id: ${node.id}). [Root => ${root.level}]',
    );
    if (removeIfNeeded) {
      removeAt(node.id, verifyDuplicates: true);
    }
    final existInRoot = !root.existInRoot(node.id);
    if (root.id == nodeTargetId && existInRoot) {
      if (node is CompositeTreeNode && node.isNotEmpty) {
        node.formatChildLevels(null, 0);
      }
      root.add(node.copyWith(nodeParent: root.id, node: node.node.copyWith(level: 0)));
      notifyListeners();
    } else {
      for (int i = 0; i < root.length; i++) {
        final rootNode = root.elementAt(i);
        if (rootNode.id == nodeTargetId) {
          if (rootNode is! CompositeTreeNode) {
            throw InvalidTypeRef(
              message:
                  'The node [${rootNode.runtimeType}-$nodeTargetId] is not a valid target to insert the ${node.runtimeType} into it. Please, ensure of the target node is a CompositeTreeNode to allow insert nodes into itself correctly',
              data: rootNode,
              time: DateTime.now(),
              targetFail: nodeTargetId,
            );
          }
          if (!rootNode.existInRoot(node.id)) {
            if (node is CompositeTreeNode) {
              node.formatChildLevels();
            }
            root.addNewChange(
              [node],
              TreeOperation.insert,
              null,
              rootNode,
            );
            rootNode
                .add(node.copyWith(nodeParent: rootNode.id, node: node.node.copyWith(level: rootNode.level + 1)));
            root[i] = rootNode.copyWith(isExpanded: true);
            notifyListeners();
            return;
          } else {
            // is already inserted and doesn't need to be searched more
            return;
          }
        } else if (rootNode is CompositeTreeNode && rootNode.isNotEmpty) {
          final inserted = insertNodeInSubComposite(rootNode, node, nodeTargetId);
          if (inserted) {
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  @override
  void insertAtRoot(TreeNode node, {bool removeIfNeeded = false}) {
    if (removeIfNeeded) removeAt(node.id, verifyDuplicates: true);
    insertAt(node, root.node.id);
    logger.writeLog(
      level: LogLevel.fine,
      message: 'Inserted node in Root level. [Root => ${root.level}]',
    );
  }

  @override
  void insertAbove(TreeNode node, String childBelowId, {bool removeIfNeeded = true}) {
    if (!existNode(childBelowId)) {
      throw NodeNotExistInTree(
        message:
            'The node $childBelowId not exist into the tree currently. Please, ensure first if the node was removed before insert any node',
        node: childBelowId,
      );
    }
    if (removeIfNeeded) {
      // removes the node from the tree
      // insert the node at the position
      removeWhere((element) => element.node.id == node.node.id, verifyDuplicates: true);
    }
    for (int i = 0; i < root.length; i++) {
      final belowNode = root.elementAt(i);
      if (belowNode.node.id == childBelowId) {
        final beforeIndex = (i - 1) == -1 ? 0 : i;
        if (node is CompositeTreeNode) {
          node.formatChildLevels();
        }
        root.addNewChange([node], TreeOperation.insertAbove, null, root);
        root.insert(
            beforeIndex, node.copyWith(nodeParent: root.id, node: node.node.copyWith(level: belowNode.level)));
        break;
      } else if (belowNode is CompositeTreeNode && belowNode.isNotEmpty) {
        final inserted = insertAboveNodeInSubComposite(belowNode, node, childBelowId);
        if (inserted) break;
      }
    }
    notifyListeners();
  }

  @override
  void clearRoot() {
    verifyState();
    root.addNewChange([], TreeOperation.clearRoot);
    root = root.copyWith(children: []);
    logger.writeLog(
      level: LogLevel.info,
      message: 'Root of the project was cleared. [Root => ${root.length}]',
    );
    notifyListeners();
  }

  @override
  bool openUntilNode(TreeNode targetNode, {bool openTargetIfNeeded = false}) {
    assert(targetNode.level >= 0);
    bool ignoreBecauseIsSubNode = false;
    CompositeTreeNode? compositeTreeNode;

    Future<bool> openWhen(List<TreeNode> tree, {bool ignoreBySubNode = false}) async {
      ignoreBecauseIsSubNode = ignoreBySubNode;
      for (int i = 0; i < tree.length; i++) {
        final TreeNode node = tree.elementAt(i);
        // the target was founded
        if (node is CompositeTreeNode && node.id == targetNode.id && openTargetIfNeeded && node.node.level == 0) {
          compositeTreeNode = node.copyWith(isExpanded: true);
        }
        if (node is CompositeTreeNode && node.id == targetNode.id && openTargetIfNeeded) {
          tree[i] = node.copyWith(isExpanded: true);
          notifyListeners();
        }
        if (node.id == targetNode.id) return true;
        if (node is CompositeTreeNode && node.isNotEmpty) {
          bool founded = await openWhen(node.children, ignoreBySubNode: true);
          if (founded) {
            return true;
          }
        }
      }
      return false;
    }

    openWhen(root.children);
    if (compositeTreeNode == null && !ignoreBecauseIsSubNode) {
      throw NodeNotExistInTree(
          message:
              'The node that we assume that need open parents until it, its id is: ${targetNode.id} was not founded',
          node: targetNode.id);
    } else if (compositeTreeNode != null) {
      updateNodeAt(compositeTreeNode!, compositeTreeNode!.id);
    }
    notifyListeners();
    return true;
  }

  @override
  bool updateNodeAt(TreeNode targetNode, String nodeId) {
    for (int i = 0; i < root.length; i++) {
      final node = root.elementAt(i);
      if (node.id == nodeId) {
        if (targetNode.node != node.node || targetNode.id != node.id) {
          throw InvalidNodeUpdate(
              message:
                  'Invalid custom node builded $targetNode. Please, ensure of create a TreeNode valid with the same Node of the passed as the argument',
              originalVersionNode: node,
              newNodeVersion: targetNode,
              reason: 'The Node of the TreeNode cannot be different than the original');
        }
        root.addNewChange(
          [targetNode],
          TreeOperation.update,
          null,
          node,
        );
        root[i] = targetNode;
        notifyListeners();
        return true;
      } else if (node is CompositeTreeNode && node.isNotEmpty) {
        final wasUpdated = updateSubNodes(node.children, targetNode, nodeId);
        if (wasUpdated) {
          root[i] = node;
          notifyListeners();
          return true;
        }
      }
    }
    return false;
  }

  @override
  TreeNode? removeAt(String nodeId, {bool ignoreRoot = false, bool verifyDuplicates = false}) {
    if (existInRoot(nodeId)) {
      root.removeWhere((element) => element.id == nodeId);
      notifyListeners();
      logger.writeLog(
        level: LogLevel.fine,
        message: 'Removed in Root level. [Root change => ${root.level}]',
      );
      if (!verifyDuplicates) return null;
    }
    for (int i = 0; i < root.length; i++) {
      final node = root.elementAt(i);
      if (node.id == nodeId && !ignoreRoot) {
        root.addNewChange(
          [node],
          TreeOperation.delete,
        );
        root.remove(node);
        logger.writeLog(
          level: LogLevel.fine,
          message: 'Removed ${node.runtimeType}(id: ${node.id}) in Root level. [Root change => ${root.level}]',
        );
        notifyListeners();
        return node;
      } else if (node is CompositeTreeNode && node.isNotEmpty) {
        final isFounded = removeChild(node, Node.base(nodeId), null);
        if (isFounded) {
          root[i] = node;
          logger.writeLog(
            level: LogLevel.fine,
            message: 'Removed sub ${node.runtimeType}(id: ${node.id}) node. [Root change => ${root.level}]',
          );
          notifyListeners();
          return node;
        }
      }
    }
    return null;
  }

  @override
  bool moveSelectionToNextSibling() {
    // TODO: implement moveSelectionToNextSibling
    throw UnimplementedError();
  }

  @override
  bool moveSelectionToUpSibling() {
    // TODO: implement moveSelectionToUpSibling
    throw UnimplementedError();
  }

  // moves the visual selection to the before child
  // from the current one
  @override
  bool moveUp() {
    if (!focused && visualSelection == null) return false;
    return false;
  }

  // moves the visual selection to the next child
  @override
  bool moveDown() {
    if (!focused && visualSelection == null) return false;
    // This will confirm to where be moved the selection
    MoveToPosition moveTo = MoveToPosition.noMove;
    String? possibleNodeToMove;

    bool confirmMove(List<TreeNode> children, String parentNodeId) {
      for (int i = 0; i < children.length; i--) {
        final node = children.elementAt(i);
        if (node.id == currentSelectedNode?.id) {
          if (node is LeafTreeNode || node is CompositeTreeNode && (!node.isExpanded || node.isEmpty)) {
            moveTo = MoveToPosition.nextSibling;
            // check if theres no child next
            // then need to move to the next one
            if (i + 1 >= children.length) {
              // We need to move directly to the next sibling of the current 
              // looped parent node id
              // 
              // Visual example of this issue
              //
              //  Parent node
              //  | Child node 1
              //  | Child node 2
              //  | Sub Parent node 3 
              //  | | Child node 1.1 
              //  | | Child node 1.2 <= Assume that we are here by now. As you see, we need to move to the next sibling of the current parent 
              //  | Child node 3 <= Using the parent id, we can move to its next child
              //
              // with this combination, the algorithm will move the selection after
              // the node passed by [possibleNodeToMove]
              moveTo = MoveToPosition.forward;
              possibleNodeToMove = parentNodeId;
              return true;
            }
            possibleNodeToMove = children.elementAtOrNull(i + 1)?.id;
            return true;
          } else if (node is CompositeTreeNode && node.isExpanded && node.isNotEmpty) {
            // Move directly to the first child when needed
            //
            // You can see this like this example:
            //
            //  Parent node
            //  | Child node 1
            //  | Child node 2
            //  | Sub Parent node 3 <= Assume that we are here by now. As you see, we need to move to the first child of this parent
            //  | | Child node 1.1  <===> The position to we need to move
            //  | | Child node 1.2
            final firstChild = node.first;
            // This combination says to the algorithm that we need to move
            // into the node (for this we use possibleNodeToMove)
            // of a [CompositeTreeNode]
            moveTo = MoveToPosition.subChildOfComposite;
            possibleNodeToMove = firstChild.id;
            return true;
          }
        } else if (node is CompositeTreeNode && node.isExpanded && node.isNotEmpty) {
          final isMoveConfirmed = confirmMove(node.children, node.id);
          if (isMoveConfirmed) return true;
        }
      }
      return false;
    }

    confirmMove(root.children, root.id);

    if (moveTo == MoveToPosition.noMove || moveTo == MoveToPosition.firstNode) {
      setVisualSelection(root.firstOrNull);
      return true;
    }

    //TODO: here we need to search the next
    // sibling to move visual selection

    return false;
  }
}
