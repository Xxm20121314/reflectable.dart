// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

// TODO(sigurdm) doc: Make NoSuchCapability messages streamlined (the same in
// both `reflectable_mirror_based.dart` and
// `reflectable_transformer_based.dart`, and explaining as well as possible
// which capability is missing.)

/// Implementation of the reflectable interface using dart mirrors.
library reflectable.src.reflectable_implementation;

import 'dart:mirrors' as dm;
import 'reflectable_base.dart';
import '../capability.dart';
import '../mirrors.dart' as rm;
import '../reflectable.dart';

bool get isTransformed => false;

/// The name of the reflectable library.
const Symbol reflectableLibrarySymbol = #reflectable.reflectable;

rm.ClassMirror wrapClassMirrorIfSupported(
    dm.ClassMirror classMirror, ReflectableImpl reflectable) {
  if (classMirror is dm.FunctionTypeMirror) {
    // TODO(sigurdm) clarify: Exactly what capabilities will allow reflecting on
    // a function is still not clear.
    return new _FunctionTypeMirrorImpl(classMirror, reflectable);
  } else {
    assert(classMirror is dm.ClassMirror);
    if (!reflectable._supportedClasses
        .contains(classMirror.originalDeclaration)) {
      throw new NoSuchCapabilityError(
          "Reflecting on class '$classMirror' without capability");
    }
    return new ClassMirrorImpl(classMirror, reflectable);
  }
}

rm.DeclarationMirror wrapDeclarationMirror(
    dm.DeclarationMirror declarationMirror, ReflectableImpl reflectable) {
  if (declarationMirror is dm.MethodMirror) {
    return new MethodMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.ParameterMirror) {
    return new _ParameterMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.VariableMirror) {
    return new VariableMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.TypeVariableMirror) {
    return new _TypeVariableMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.TypedefMirror) {
    return new _TypedefMirrorImpl(declarationMirror, reflectable);
  } else if (declarationMirror is dm.ClassMirror) {
    // Covers FunctionTypeMirror and ClassMirror.
    return wrapClassMirrorIfSupported(declarationMirror, reflectable);
  } else {
    assert(declarationMirror is dm.LibraryMirror);
    return new _LibraryMirrorImpl(declarationMirror, reflectable);
  }
}

rm.InstanceMirror wrapInstanceMirror(
    dm.InstanceMirror instanceMirror, ReflectableImpl reflectable) {
  if (instanceMirror is dm.ClosureMirror) {
    return new _ClosureMirrorImpl(instanceMirror, reflectable);
  } else {
    assert(instanceMirror is dm.InstanceMirror);
    return new _InstanceMirrorImpl(instanceMirror, reflectable);
  }
}

rm.ObjectMirror wrapObjectMirror(
    dm.ObjectMirror m, ReflectableImpl reflectable) {
  if (m is dm.LibraryMirror) {
    return new _LibraryMirrorImpl(m, reflectable);
  } else if (m is dm.InstanceMirror) {
    return wrapInstanceMirror(m, reflectable);
  } else {
    assert(m is dm.ClassMirror);
    return wrapClassMirrorIfSupported(m, reflectable);
  }
}

rm.TypeMirror wrapTypeMirror(
    dm.TypeMirror typeMirror, ReflectableImpl reflectable) {
  if (typeMirror is dm.TypeVariableMirror) {
    return new _TypeVariableMirrorImpl(typeMirror, reflectable);
  } else if (typeMirror is dm.TypedefMirror) {
    return new _TypedefMirrorImpl(typeMirror, reflectable);
  } else if (typeMirror.reflectedType == dynamic) {
    return new _SpecialTypeMirrorImpl(typeMirror, reflectable);
  } else {
    assert(typeMirror is dm.ClassMirror);
    return wrapClassMirrorIfSupported(typeMirror, reflectable);
  }
}

rm.CombinatorMirror wrapCombinatorMirror(dm.CombinatorMirror combinatorMirror) {
  return new _CombinatorMirrorImpl(combinatorMirror);
}

dm.ClassMirror unwrapClassMirror(rm.ClassMirror m) {
  if (m is ClassMirrorImpl) {
    // This also works for _FunctionTypeMirrorImpl
    return m._classMirror;
  } else {
    throw new ArgumentError("Unexpected subtype of ClassMirror");
  }
}

dm.TypeMirror unwrapTypeMirror(rm.TypeMirror TypeMirror) {
  if (TypeMirror is _TypeMirrorImpl) {
    return TypeMirror._typeMirror;
  } else {
    throw new ArgumentError("Unexpected subtype of TypeMirror");
  }
}

/// Returns true iff an element of the [metadata] is supported by the
/// [capability].
bool metadataSupported(
    List<dm.InstanceMirror> metadata, MetadataQuantifiedCapability capability) {
  return metadata
      .map((dm.InstanceMirror x) => x.reflectee.runtimeType)
      .contains(capability.metadataType);
}

bool impliesUpwardsClosure(List<ReflectCapability> capabilities) {
  return capabilities.any((ReflectCapability capability) =>
      capability is SuperclassQuantifyCapability);
}

List<dm.ClassMirror> extractUpwardsClosureBounds(
    List<ReflectCapability> capabilities) {
  List<dm.ClassMirror> result = <dm.ClassMirror>[];
  capabilities.forEach((ReflectCapability capability) {
    if (capability is SuperclassQuantifyCapability) {
      dm.TypeMirror typeMirror = dm.reflectType(capability.upperBound);
      if (typeMirror is dm.ClassMirror) {
        result.add(typeMirror);
      } else {
        throw new ArgumentError("Unexpected kind of upper bound specified "
            "for a `SuperclassQuantifyCapability`: $typeMirror.");
      }
    }
  });
  return result;
}

bool impliesDeclarations(List<ReflectCapability> capabilities) {
  return capabilities.contains(declarationsCapability);
}

bool impliesTypes(List<ReflectCapability> capabilities) {
  if (!impliesDeclarations(capabilities)) return false;
  return capabilities.any((ReflectCapability capability) {
    return capability is TypeCapability;
  });
}

/// Returns true if [classMirror] supports reflective invoke of the
/// instance-member named [name] according to the
/// capabilities of [reflectable].
bool reflectableSupportsInstanceInvoke(
    ReflectableImpl reflectable, String name, dm.ClassMirror classMirror) {
  Symbol nameSymbol = new Symbol(name);

  bool predicate(ApiReflectCapability capability) {
    if (capability == invokingCapability ||
        capability == instanceInvokeCapability) {
      return true;
    } else if (capability is InstanceInvokeCapability) {
      return new RegExp(capability.namePattern).hasMatch(name);
    } else if (capability is InstanceInvokeMetaCapability) {
      // We have to use 'declarations' here instead of instanceMembers, because
      // the synthetic field mirrors generated from fields do not have metadata
      // attached.
      // TODO(eernst) clarify: If we use `declarations` in a context where
      // `instanceMembers` is expected, we must iterate over all superclasses
      // "manually". Check whether there is a bug here, alternatively update
      // the above comment.
      dm.DeclarationMirror declarationMirror =
          classMirror.declarations[nameSymbol];
      return declarationMirror != null &&
          metadataSupported(declarationMirror.metadata, capability);
    } else {
      return false;
    }
  }

  return reflectable.hasCapability(predicate);
}

/// Returns true iff [reflectable] supports static invoke of [name].
bool reflectableSupportsStaticInvoke(ReflectableImpl reflectable, String name,
    List<dm.InstanceMirror> metadata) {
  bool predicate(ApiReflectCapability capability) {
    if (capability == staticInvokeCapability) {
      return true;
    } else if (capability is StaticInvokeCapability) {
      return new RegExp(capability.namePattern).hasMatch(name);
    }
    if (capability is StaticInvokeMetaCapability) {
      return metadataSupported(metadata, capability);
    }
    return false;
  }

  return reflectable.hasCapability(predicate);
}

/// Returns true iff [reflectable] supports top-level invoke of [name].
bool reflectableSupportsTopLevelInvoke(ReflectableImpl reflectable, String name,
    List<dm.InstanceMirror> metadata) {
  // We don't have to check for `libraryCapability` because this method is only
  // ever called from the methods of a `LibraryMirrorImpl` and the existence of
  // an instance of a `LibraryMirrorImpl` implies the `libraryMirrorCapability`.
  // Finally, we do not have to check for the capability as given to a subtype,
  // because a library is never a subtype of anything.
  return reflectable.hasCapability((ApiReflectCapability capability) {
    if (capability == topLevelInvokeCapability) {
      return true;
    } else if (capability is TopLevelInvokeCapability) {
      return new RegExp(capability.namePattern).hasMatch(name);
    }
    if (capability is TopLevelInvokeMetaCapability) {
      return metadataSupported(metadata, capability);
    }
    return false;
  });
}

/// Returns true iff [reflectable] supports invoke of [name].
bool reflectableSupportsConstructorInvoke(
    ReflectableImpl reflectable, dm.ClassMirror classMirror, String name) {
  bool predicate(ApiReflectCapability capability) {
    if (capability == newInstanceCapability) {
      return true;
    } else if (capability is NewInstanceCapability) {
      return new RegExp(capability.namePattern).hasMatch(name);
    } else if (capability is NewInstanceMetaCapability) {
      dm.MethodMirror constructorMirror = classMirror.declarations.values
          .firstWhere((dm.DeclarationMirror declarationMirror) {
        Symbol nameSymbol = new Symbol(name);
        return declarationMirror is dm.MethodMirror &&
            declarationMirror.isConstructor &&
            declarationMirror.constructorName == nameSymbol;
      });
      if (constructorMirror == null ||
          !constructorMirror.isConstructor) return false;
      return metadataSupported(constructorMirror.metadata, metadataCapability);
    }
    return false;
  }

  return reflectable.hasCapability(predicate);
}

bool reflectableSupportsDeclarations(Reflectable reflectable) {
  bool predicate(ApiReflectCapability capability) =>
      capability == declarationsCapability;
  return reflectable.hasCapability(predicate);
}

/// Returns [setterName] with final "=" removed.
/// If the it does not have a final "=" it is returned as is.
String _setterToGetter(String setterName) {
  if (!setterName.endsWith("=")) {
    return setterName;
  }
  return setterName.substring(0, setterName.length - 1);
}

/// Returns [getterName] with a final "=" added.
/// If [getter] already ends with "=" an error is thrown.
String _getterToSetter(String getterName) {
  if (getterName.endsWith("=")) {
    throw new ArgumentError(
        "$getterName is a setter name (ends with `=`) already.");
  }
  return '$getterName=';
}

bool _supportsType(List<ReflectCapability> capabilities) {
  return capabilities.any((ReflectCapability capability) =>
      capability is TypeCapability);
}

abstract class _ObjectMirrorImplMixin implements rm.ObjectMirror {
  ReflectableImpl get _reflectable;
}

class _LibraryMirrorImpl extends _DeclarationMirrorImpl
    with _ObjectMirrorImplMixin
    implements rm.LibraryMirror {
  dm.LibraryMirror get _libraryMirror => _declarationMirror;

  _LibraryMirrorImpl(dm.LibraryMirror m, ReflectableImpl reflectable)
      : super(m, reflectable) {}

  @override
  Uri get uri => _libraryMirror.uri;

  @override
  Map<String, rm.DeclarationMirror> get declarations {
    if (!reflectableSupportsDeclarations(_reflectable)) {
      throw new NoSuchCapabilityError(
          "Attempt to get declarations without capability");
    }
    Map<Symbol, dm.DeclarationMirror> decls = _libraryMirror.declarations;
    Iterable<Symbol> relevantKeys = decls.keys.where((k) {
      List<dm.InstanceMirror> metadata = decls[k].metadata;
      for (var item in metadata) {
        if (item.hasReflectee && item.reflectee is ReflectableImpl) return true;
      }
      return false;
    });
    return new Map<String, rm.DeclarationMirror>.fromIterable(relevantKeys,
        key: (k) => dm.MirrorSystem.getName(k),
        value: (v) => wrapDeclarationMirror(decls[v], _reflectable));
  }

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    if (!reflectableSupportsTopLevelInvoke(_reflectable, memberName,
        _libraryMirror.declarations[new Symbol(memberName)].metadata)) {
      throw new NoSuchInvokeCapabilityError(
          _receiver, memberName, positionalArguments, namedArguments);
    }

    return _libraryMirror
        .invoke(new Symbol(memberName), positionalArguments, namedArguments)
        .reflectee;
  }

  @override
  Object invokeGetter(String getterName) {
    if (!reflectableSupportsTopLevelInvoke(_reflectable, getterName,
        _libraryMirror.declarations[new Symbol(getterName)].metadata)) {
      throw new NoSuchInvokeCapabilityError(_receiver, getterName, [], null);
    }
    Symbol getterNameSymbol = new Symbol(getterName);
    return _libraryMirror.getField(getterNameSymbol).reflectee;
  }

  @override
  Object invokeSetter(String setterName, Object value) {
    if (!reflectableSupportsTopLevelInvoke(_reflectable, setterName,
        _libraryMirror.declarations[new Symbol(setterName)].metadata)) {
      throw new NoSuchInvokeCapabilityError(
          _receiver, setterName, [value], null);
    }
    String getterName = _setterToGetter(setterName);
    Symbol getterNameSymbol = new Symbol(getterName);
    return _libraryMirror.setField(getterNameSymbol, value).reflectee;
  }

  @override
  bool operator ==(other) {
    return other is _LibraryMirrorImpl
        ? _libraryMirror == other._libraryMirror
        : false;
  }

  @override
  int get hashCode => _libraryMirror.hashCode;

  @override
  List<rm.LibraryDependencyMirror> get libraryDependencies {
    return _libraryMirror.libraryDependencies
        .map((dep) => new _LibraryDependencyMirrorImpl(dep, _reflectable))
        .toList();
  }

  get _receiver => "top-level";

  @override
  String toString() {
    return "_LibraryMirrorImpl('${_libraryMirror.toString()}')";
  }
}

class _LibraryDependencyMirrorImpl implements rm.LibraryDependencyMirror {
  final dm.LibraryDependencyMirror _libraryDependencyMirror;
  final ReflectableImpl _reflectable;

  _LibraryDependencyMirrorImpl(
      this._libraryDependencyMirror, this._reflectable);

  @override
  bool get isImport => _libraryDependencyMirror.isImport;

  @override
  bool get isExport => _libraryDependencyMirror.isExport;

  @override
  rm.LibraryMirror get sourceLibrary {
    return new _LibraryMirrorImpl(
        _libraryDependencyMirror.sourceLibrary, _reflectable);
  }

  @override
  rm.LibraryMirror get targetLibrary {
    return new _LibraryMirrorImpl(
        _libraryDependencyMirror.targetLibrary, _reflectable);
  }

  @override
  String get prefix => dm.MirrorSystem.getName(_libraryDependencyMirror.prefix);

  @override
  List<Object> get metadata =>
      _libraryDependencyMirror.metadata.map((m) => m.reflectee).toList();

  @override
  rm.SourceLocation get location {
    return new _SourceLocationImpl(_libraryDependencyMirror.location);
  }

  @override
  List<rm.CombinatorMirror> get combinators {
    return _libraryDependencyMirror.combinators
        .map(wrapCombinatorMirror)
        .toList();
  }

  @override
  bool get isDeferred => _libraryDependencyMirror.isDeferred;

  @override
  String toString() {
    return "_LibraryDependencyMirrorImpl('${_libraryDependencyMirror}')";
  }
}

class _InstanceMirrorImpl extends _ObjectMirrorImplMixin
    implements rm.InstanceMirror {
  final dm.InstanceMirror _instanceMirror;
  final ReflectableImpl _reflectable;

  _InstanceMirrorImpl(this._instanceMirror, this._reflectable);

  @override
  rm.TypeMirror get type => wrapTypeMirror(_instanceMirror.type, _reflectable);

  @override
  bool get hasReflectee => _instanceMirror.hasReflectee;

  @override
  get reflectee => _instanceMirror.reflectee;

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    if (reflectableSupportsInstanceInvoke(
        _reflectable, memberName, _instanceMirror.type)) {
      Symbol memberNameSymbol = new Symbol(memberName);
      return _instanceMirror
          .invoke(memberNameSymbol, positionalArguments, namedArguments)
          .reflectee;
    }
    throw new NoSuchInvokeCapabilityError(
        _receiver, memberName, positionalArguments, namedArguments);
  }

  @override
  Object invokeGetter(String fieldName) {
    if (reflectableSupportsInstanceInvoke(
        _reflectable, fieldName, _instanceMirror.type)) {
      Symbol fieldNameSymbol = new Symbol(fieldName);
      return _instanceMirror.getField(fieldNameSymbol).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(_receiver, fieldName, [], null);
  }

  @override
  Object invokeSetter(String setterName, Object value) {
    if (reflectableSupportsInstanceInvoke(
        _reflectable, setterName, _instanceMirror.type)) {
      String getterName = _setterToGetter(setterName);
      Symbol getterNameSymbol = new Symbol(getterName);
      return _instanceMirror.setField(getterNameSymbol, value).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(_receiver, setterName, [value], null);
  }

  @override
  bool operator ==(other) => other is _InstanceMirrorImpl
      ? _instanceMirror == other._instanceMirror
      : false;

  @override
  int get hashCode => _instanceMirror.hashCode;

  @override
  delegate(Invocation invocation) => _instanceMirror.delegate(invocation);

  get _receiver => _instanceMirror.reflectee;

  @override
  String toString() => "_InstanceMirrorImpl('${_instanceMirror}')";
}

class ClassMirrorImpl extends _TypeMirrorImpl
    with _ObjectMirrorImplMixin
    implements rm.ClassMirror {
  dm.ClassMirror get _classMirror => _declarationMirror;

  ClassMirrorImpl(dm.ClassMirror classMirror, ReflectableImpl reflectable)
      : super(classMirror, reflectable) {}

  @override
  List<rm.TypeVariableMirror> get typeVariables {
    return _classMirror.typeVariables.map((v) {
      return new _TypeVariableMirrorImpl(v, _reflectable);
    }).toList();
  }

  @override
  List<rm.TypeMirror> get typeArguments => _classMirror.typeArguments.map((a) {
        return wrapTypeMirror(a, _reflectable);
      }).toList();

  @override
  rm.ClassMirror get superclass {
    dm.ClassMirror sup = _classMirror.superclass;
    if (sup == null) return null; // For `Object`, do as `dm`.
    return wrapClassMirrorIfSupported(sup, _reflectable);
  }

  @override
  List<rm.ClassMirror> get superinterfaces {
    List<dm.ClassMirror> superinterfaces = _classMirror.superinterfaces;
    return superinterfaces
        .where((dm.ClassMirror superinterface) => (_reflectable
            ._supportedClasses.contains(superinterface.originalDeclaration)))
        .map((dm.TypeMirror superinterface) {
      return wrapTypeMirror(superinterface, _reflectable);
    }).toList();
  }

  @override
  bool get isAbstract => _classMirror.isAbstract;

  @override
  Map<String, rm.DeclarationMirror> get declarations {
    if (!reflectableSupportsDeclarations(_reflectable)) {
      throw new NoSuchCapabilityError(
          "Attempt to get declarations without capability");
    }
    // TODO(sigurdm) future: Possibly cache this.
    Map<String, rm.DeclarationMirror> result =
        new Map<String, rm.DeclarationMirror>();
    _classMirror.declarations
        .forEach((Symbol nameSymbol, dm.DeclarationMirror declarationMirror) {
      String name = dm.MirrorSystem.getName(nameSymbol);
      if (declarationMirror is dm.MethodMirror) {
        if (_isMixin && declarationMirror.isStatic) return;
        bool included = false;
        if (declarationMirror.isConstructor) {
          // Factory constructors are static, others not, so this decision
          // is made independently of `isStatic`.
          included = included ||
              reflectableSupportsConstructorInvoke(
                  _reflectable, _classMirror, name);
        } else {
          // `declarationMirror` is a non-constructor.
          if (declarationMirror.isStatic) {
            // `declarationMirror` is a static method/getter/setter.
            included = included ||
                reflectableSupportsStaticInvoke(
                    _reflectable, name, declarationMirror.metadata);
          } else {
            // `declarationMirror` is an instance method/getter/setter.
            included = included ||
                reflectableSupportsInstanceInvoke(
                    _reflectable, name, _classMirror);
          }
        }
        if (included) {
          result[name] = wrapDeclarationMirror(declarationMirror, _reflectable);
        }
      } else if (declarationMirror is dm.VariableMirror) {
        if (_isMixin && declarationMirror.isStatic) return;
        // For variableMirrors we test both for support of the name and the
        // derived setter name.
        bool included = false;
        if (declarationMirror.isStatic) {
          included = included ||
              reflectableSupportsStaticInvoke(
                  _reflectable, name, declarationMirror.metadata) ||
              reflectableSupportsStaticInvoke(_reflectable,
                  _getterToSetter(name), declarationMirror.metadata);
        } else {
          included = included ||
              reflectableSupportsInstanceInvoke(
                  _reflectable, name, _classMirror) ||
              reflectableSupportsInstanceInvoke(
                  _reflectable, _getterToSetter(name), _classMirror);
        }
        if (included) {
          result[name] = wrapDeclarationMirror(declarationMirror, _reflectable);
        }
      } else {
        // TODO(sigurdm) implement: Consider capabilities for other
        // declarations; the additional subtypes of DeclarationMirror are
        // LibraryMirror (global), TypeMirror and the 4 subtypes thereof,
        // and ParameterMirror (declared in a method, not class), so the
        // only case that needs further clarification is TypeVariableMirror.
        // For now we just let it through.
        result[name] = wrapDeclarationMirror(declarationMirror, _reflectable);
      }
    });
    return result;
  }

  @override
  Map<String, rm.MethodMirror> get instanceMembers {
    // TODO(sigurdm) implement: Only expose members that are allowed
    // by the capabilities of the reflectable.
    Map<Symbol, dm.MethodMirror> members = _classMirror.instanceMembers;
    return new Map<String, rm.MethodMirror>.fromIterable(members.keys,
        key: (k) => dm.MirrorSystem.getName(k),
        value: (v) => new MethodMirrorImpl(members[v], _reflectable));
  }

  @override
  Map<String, rm.MethodMirror> get staticMembers {
    // TODO(sigurdm) implement: Only expose members that are allowed by the
    // capabilities of the reflectable.
    Map<Symbol, dm.MethodMirror> members = _classMirror.staticMembers;
    return new Map<String, rm.MethodMirror>.fromIterable(members.keys,
        key: (k) => dm.MirrorSystem.getName(k),
        value: (v) => new MethodMirrorImpl(members[v], _reflectable));
  }

  @override
  rm.ClassMirror get mixin {
    return wrapClassMirrorIfSupported(_classMirror.mixin, _reflectable);
  }

  @override
  Object newInstance(String constructorName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    if (!reflectableSupportsConstructorInvoke(
        _reflectable, _classMirror, constructorName)) {
      throw new NoSuchInvokeCapabilityError(
          _classMirror, constructorName, positionalArguments, namedArguments);
    }
    Symbol constructorNameSymbol = new Symbol(constructorName);
    return _classMirror
        .newInstance(constructorNameSymbol, positionalArguments, namedArguments)
        .reflectee;
  }

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    dm.DeclarationMirror declaration =
        _classMirror.declarations[new Symbol(memberName)];
    List<Object> metadata = declaration == null ? null : declaration.metadata;
    if (reflectableSupportsStaticInvoke(_reflectable, memberName, metadata)) {
      Symbol memberNameSymbol = new Symbol(memberName);
      return _classMirror
          .invoke(memberNameSymbol, positionalArguments, namedArguments)
          .reflectee;
    }
    throw new NoSuchInvokeCapabilityError(
        _receiver, memberName, positionalArguments, namedArguments);
  }

  @override
  Object invokeGetter(String getterName) {
    if (reflectableSupportsStaticInvoke(_reflectable, getterName,
        _classMirror.declarations[new Symbol(getterName)].metadata)) {
      Symbol getterNameSymbol = new Symbol(getterName);
      return _classMirror.getField(getterNameSymbol).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(_receiver, getterName, [], null);
  }

  @override
  Object invokeSetter(String setterName, Object value) {
    if (reflectableSupportsStaticInvoke(_reflectable, setterName,
        _classMirror.declarations[new Symbol(setterName)].metadata)) {
      String getterName = _setterToGetter(setterName);
      Symbol getterNameSymbol = new Symbol(getterName);
      return _classMirror.setField(getterNameSymbol, value).reflectee;
    }
    throw new NoSuchInvokeCapabilityError(_receiver, setterName, [value], null);
  }

  @override
  bool operator ==(other) {
    return other is ClassMirrorImpl
        ? _classMirror == other._classMirror
        : false;
  }

  @override
  int get hashCode => _classMirror.hashCode;

  @override
  bool isSubclassOf(rm.ClassMirror other) {
    return _classMirror.isSubclassOf(unwrapClassMirror(other));
  }

  get _receiver => _classMirror.reflectedType;

  @override
  String toString() => "ClassMirrorImpl('${_classMirror}')";

  @override
  Function invoker(String memberName) {
    Symbol memberNameSymbol = new Symbol(memberName);
    Function helper(Object o) {
      dm.InstanceMirror receiverMirror = dm.reflect(o);
      dm.InstanceMirror memberMirror =
          receiverMirror.getField(memberNameSymbol);
      return memberMirror.reflectee;
    }
    return helper;
  }

  @override
  rm.LibraryMirror get owner {
    if (_reflectable._supportsLibraries) return super.owner;
    throw new NoSuchCapabilityError(
        "Trying to get owner of class '$qualifiedName' "
        "without 'libraryCapability'");
  }

  bool get _isMixin => _classMirror.mixin != _classMirror;
}

class _FunctionTypeMirrorImpl extends ClassMirrorImpl
    implements rm.FunctionTypeMirror {
  dm.FunctionTypeMirror get _functionTypeMirror => _classMirror;

  _FunctionTypeMirrorImpl(
      dm.FunctionTypeMirror functionTypeMirror, ReflectableImpl reflectable)
      : super(functionTypeMirror, reflectable);

  @override
  rm.MethodMirror get callMethod {
    return new MethodMirrorImpl(_functionTypeMirror.callMethod, _reflectable);
  }

  @override
  List<rm.ParameterMirror> get parameters {
    return _functionTypeMirror.parameters
        .map((dm.ParameterMirror parameterMirror) {
      return new _ParameterMirrorImpl(parameterMirror, _reflectable);
    });
  }

  @override
  rm.TypeMirror get returnType {
    // TODO(eernst) clarify: Is it really true that we cannot detect the
    // type void other than looking at its name?
    if (_functionTypeMirror.returnType.simpleName == "void") {
      return new _VoidMirrorImpl();
    }
    return wrapTypeMirror(_functionTypeMirror.returnType, _reflectable);
  }
}

abstract class _DeclarationMirrorImpl implements rm.DeclarationMirror {
  final dm.DeclarationMirror _declarationMirror;
  final ReflectableImpl _reflectable;

  _DeclarationMirrorImpl(this._declarationMirror, this._reflectable);

  @override
  String get simpleName =>
      dm.MirrorSystem.getName(_declarationMirror.simpleName);

  @override
  String get qualifiedName =>
      dm.MirrorSystem.getName(_declarationMirror.qualifiedName);

  @override
  rm.DeclarationMirror get owner {
    return wrapDeclarationMirror(_declarationMirror.owner, _reflectable);
  }

  @override
  bool get isPrivate => _declarationMirror.isPrivate;

  @override
  bool get isTopLevel => _declarationMirror.isTopLevel;

  @override
  List<Object> get metadata {
    if (_reflectable.capabilities.contains(metadataCapability)) {
      return _declarationMirror.metadata.map((m) => m.reflectee).toList();
    }
    throw new NoSuchCapabilityError(
        "Attempt to get metadata witout 'metadataCapability'");
  }

  @override
  rm.SourceLocation get location {
    return new _SourceLocationImpl(_declarationMirror.location);
  }

  @override
  String toString() {
    return "_DeclarationMirrorImpl('${_declarationMirror}')";
  }
}

class MethodMirrorImpl extends _DeclarationMirrorImpl
    implements rm.MethodMirror {
  dm.MethodMirror get _methodMirror => _declarationMirror;

  MethodMirrorImpl(dm.MethodMirror mm, ReflectableImpl reflectable)
      : super(mm, reflectable);

  @override
  rm.TypeMirror get returnType {
    // TODO(eernst) clarify: Is there really no other way to detect
    // the `void` type than looking at its name?
    if (_methodMirror.returnType.simpleName == const Symbol("void")) {
      return new _VoidMirrorImpl();
    }
    return wrapTypeMirror(_methodMirror.returnType, _reflectable);
  }

  @override
  String get source => _methodMirror.source;

  @override
  List<rm.ParameterMirror> get parameters {
    return _methodMirror.parameters.map((p) {
      return new _ParameterMirrorImpl(p, _reflectable);
    }).toList();
  }

  @override
  bool get isStatic => _methodMirror.isStatic;

  @override
  bool get isAbstract => _methodMirror.isAbstract;

  @override
  bool get isSynthetic => _methodMirror.isSynthetic;

  @override
  bool get isRegularMethod => _methodMirror.isRegularMethod;

  @override
  bool get isOperator => _methodMirror.isOperator;

  @override
  bool get isGetter => _methodMirror.isGetter;

  @override
  bool get isSetter => _methodMirror.isSetter;

  @override
  bool get isConstructor => _methodMirror.isConstructor;

  @override
  String get constructorName =>
      dm.MirrorSystem.getName(_methodMirror.constructorName);

  @override
  bool get isConstConstructor => _methodMirror.isConstConstructor;

  @override
  bool get isGenerativeConstructor => _methodMirror.isGenerativeConstructor;

  @override
  bool get isRedirectingConstructor => _methodMirror.isRedirectingConstructor;

  @override
  bool get isFactoryConstructor => _methodMirror.isFactoryConstructor;

  @override
  bool operator ==(other) {
    return other is MethodMirrorImpl
        ? _methodMirror == other._methodMirror
        : false;
  }

  @override
  int get hashCode => _methodMirror.hashCode;

  @override
  String toString() => "_MethodMirrorImpl('${_methodMirror}')";
}

class _ClosureMirrorImpl extends _InstanceMirrorImpl
    implements rm.ClosureMirror {
  dm.ClosureMirror get _closureMirror => _instanceMirror;

  _ClosureMirrorImpl(
      dm.ClosureMirror closureMirror, ReflectableImpl reflectable)
      : super(closureMirror, reflectable);

  @override
  Object apply(List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    return _closureMirror.apply(positionalArguments, namedArguments).reflectee;
  }

  @override
  rm.MethodMirror get function {
    return new MethodMirrorImpl(_closureMirror.function, _reflectable);
  }

  @override
  String toString() => "_ClosureMirrorImpl('${_closureMirror}')";
}

class VariableMirrorImpl extends _DeclarationMirrorImpl
    implements rm.VariableMirror {
  dm.VariableMirror get _variableMirror => _declarationMirror;

  VariableMirrorImpl(dm.VariableMirror vm, ReflectableImpl reflectable)
      : super(vm, reflectable);

  @override
  rm.TypeMirror get type {
    if (_supportsType(_reflectable.capabilities)) {
      return wrapTypeMirror(_variableMirror.type, _reflectable);
    }
    throw new NoSuchCapabilityError("Attempt to get type without capability");
  }

  @override
  bool get isStatic => _variableMirror.isStatic;

  @override
  bool get isFinal => _variableMirror.isFinal;

  @override
  bool get isConst => _variableMirror.isConst;

  @override
  bool operator ==(other) => other is VariableMirrorImpl
      ? _variableMirror == other._variableMirror
      : false;

  @override
  int get hashCode => _variableMirror.hashCode;

  @override
  String toString() => "VariableMirrorImpl('${_variableMirror}')";
}

class _ParameterMirrorImpl extends VariableMirrorImpl
    implements rm.ParameterMirror {
  dm.ParameterMirror get _parameterMirror => _declarationMirror;

  _ParameterMirrorImpl(dm.ParameterMirror pm, ReflectableImpl reflectable)
      : super(pm, reflectable);

  @override
  bool get isOptional => _parameterMirror.isOptional;

  @override
  bool get isNamed => _parameterMirror.isNamed;

  @override
  bool get hasDefaultValue => _parameterMirror.hasDefaultValue;

  @override
  Object get defaultValue {
    if (_parameterMirror.hasDefaultValue) {
      return _parameterMirror.defaultValue.reflectee;
    }
    return null;
  }

  @override
  bool operator ==(other) => other is _ParameterMirrorImpl
      ? _parameterMirror == other._parameterMirror
      : false;

  @override
  int get hashCode => _parameterMirror.hashCode;

  @override
  String toString() => "_ParameterMirrorImpl('${_parameterMirror}')";
}

abstract class _TypeMirrorImpl extends _DeclarationMirrorImpl
    implements rm.TypeMirror {
  dm.TypeMirror get _typeMirror => _declarationMirror;

  _TypeMirrorImpl(dm.TypeMirror typeMirror, ReflectableImpl reflectable)
      : super(typeMirror, reflectable);

  @override
  bool get hasReflectedType => _typeMirror.hasReflectedType;

  @override
  bool isAssignableTo(rm.TypeMirror other) {
    return _typeMirror.isAssignableTo(unwrapTypeMirror(other));
  }

  @override
  bool get isOriginalDeclaration => _typeMirror.isOriginalDeclaration;

  @override
  bool isSubtypeOf(rm.TypeMirror other) {
    return _typeMirror.isSubtypeOf(unwrapTypeMirror(other));
  }

  @override
  rm.TypeMirror get originalDeclaration {
    return wrapTypeMirror(_typeMirror.originalDeclaration, _reflectable);
  }

  @override
  Type get reflectedType => _typeMirror.reflectedType;

  @override
  List<rm.TypeMirror> get typeArguments {
    return _typeMirror.typeArguments.map((dm.TypeMirror typeArgument) {
      return wrapTypeMirror(typeArgument, _reflectable);
    }).toList();
  }

  @override
  List<rm.TypeVariableMirror> get typeVariables {
    return _typeMirror.typeVariables
        .map((dm.TypeVariableMirror typeVariableMirror) {
      return new _TypeVariableMirrorImpl(typeVariableMirror, _reflectable);
    }).toList();
  }
}

class _TypeVariableMirrorImpl extends _TypeMirrorImpl
    implements rm.TypeVariableMirror {
  dm.TypeVariableMirror get _typeVariableMirror => _typeMirror;

  _TypeVariableMirrorImpl(
      dm.TypeVariableMirror typeVariableMirror, ReflectableImpl reflectable)
      : super(typeVariableMirror, reflectable);

  @override
  bool get isStatic => _typeVariableMirror.isStatic;

  @override
  operator ==(other) {
    return other is _TypeVariableMirrorImpl &&
        other._typeVariableMirror == _typeVariableMirror;
  }

  @override
  int get hashCode => _typeVariableMirror.hashCode;

  @override
  rm.TypeMirror get upperBound {
    return wrapTypeMirror(_typeVariableMirror.upperBound, _reflectable);
  }

  @override
  String toString() {
    return "_TypeVariableMirrorImpl('${_typeVariableMirror}')";
  }
}

class _TypedefMirrorImpl extends _TypeMirrorImpl implements rm.TypedefMirror {
  dm.TypedefMirror get _typedefMirror => _typeMirror;

  _TypedefMirrorImpl(
      dm.TypedefMirror typedefMirror, ReflectableImpl reflectable)
      : super(typedefMirror, reflectable);

  @override
  rm.FunctionTypeMirror get referent {
    return new _FunctionTypeMirrorImpl(_typedefMirror.referent, _reflectable);
  }

  @override operator ==(other) {
    return other is _TypedefMirrorImpl &&
        other._typedefMirror == _typedefMirror;
  }

  @override
  int get hashCode => _typedefMirror.hashCode;

  @override
  String toString() {
    return "_TypedefMirrorImpl('${_typedefMirror}')";
  }
}

class _SpecialTypeMirrorImpl extends _TypeMirrorImpl {
  _SpecialTypeMirrorImpl(dm.TypeMirror typeMirror, ReflectableImpl reflectable)
      : super(typeMirror, reflectable);

  @override operator ==(other) {
    return other is _SpecialTypeMirrorImpl && other._typeMirror == _typeMirror;
  }

  @override
  int get hashCode => _typeMirror.hashCode;

  @override
  String toString() {
    return "_SpecialTypeMirrorImpl('${_typeMirror}')";
  }
}

class _CombinatorMirrorImpl implements rm.CombinatorMirror {
  dm.CombinatorMirror _combinatorMirror;

  _CombinatorMirrorImpl(this._combinatorMirror);

  @override
  List<String> get identifiers =>
      _combinatorMirror.identifiers.map(dm.MirrorSystem.getName);

  @override
  bool get isHide => _combinatorMirror.isHide;

  @override
  bool get isShow => _combinatorMirror.isShow;

  @override
  operator ==(other) {
    return other is _CombinatorMirrorImpl &&
        other._combinatorMirror == _combinatorMirror;
  }

  @override
  int get hashCode => _combinatorMirror.hashCode;

  @override
  String toString() {
    return "_CombinatorMirrorImpl('${_combinatorMirror}')";
  }
}

class _VoidMirrorImpl implements rm.TypeMirror {
  @override
  bool get hasReflectedType => false;

  @override
  Type get reflectedType => throw new NoSuchCapabilityError(
      "Attempt to get the reflected type of 'void'");

  @override
  List<TypeVariableMirror> get typeVariables => [];

  @override
  List<TypeMirror> get typeArguments => [];

  @override
  bool get isOriginalDeclaration => true;

  @override
  TypeMirror get originalDeclaration => this;

  @override
  bool isSubtypeOf(TypeMirror other) =>
      other.hasReflectedType && other.reflectedType == dynamic;

  @override
  bool isAssignableTo(TypeMirror other) => isSubtypeOf(other);

  @override
  String get simpleName => "void";

  // TODO(eernst) implement: do as 'dart:mirrors' does.
  @override
  get owner => null;

  // TODO(eernst) implement: do as 'dart:mirrors' does.
  @override
  List<Object> get metadata => <Object>[];

  @override
  String get qualifiedName => simpleName;

  @override
  bool get isPrivate => false;

  // It is allowed to return null.
  @override
  get location => null;

  @override
  bool get isTopLevel => true;
}

class _SourceLocationImpl implements rm.SourceLocation {
  dm.SourceLocation _sourceLocation;

  _SourceLocationImpl(this._sourceLocation);

  @override
  int get line => _sourceLocation.line;

  @override
  int get column => _sourceLocation.column;

  @override
  Uri get sourceUri => _sourceLocation.sourceUri;

  @override operator ==(other) {
    return other is _SourceLocationImpl &&
        other._sourceLocation == _sourceLocation;
  }

  @override
  int get hashCode => _sourceLocation.hashCode;

  @override
  String toString() {
    return "_SourceLocationImpl('${_sourceLocation}')";
  }
}

/// An implementation of [ReflectableInterface] based on dart:mirrors.
class ReflectableImpl extends ReflectableBase implements ReflectableInterface {
  /// Const constructor, to enable usage as metadata, allowing for varargs
  /// style invocation with up to ten arguments.
  const ReflectableImpl(
      [ReflectCapability cap0 = null,
      ReflectCapability cap1 = null,
      ReflectCapability cap2 = null,
      ReflectCapability cap3 = null,
      ReflectCapability cap4 = null,
      ReflectCapability cap5 = null,
      ReflectCapability cap6 = null,
      ReflectCapability cap7 = null,
      ReflectCapability cap8 = null,
      ReflectCapability cap9 = null])
      : super(cap0, cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9);

  const ReflectableImpl.fromList(List<ReflectCapability> capabilities)
      : super.fromList(capabilities);

  bool _canReflect(dm.InstanceMirror mirror) =>
      _supportedClasses.contains(mirror.type.originalDeclaration);

  /// Determines whether reflection is supported for the given [o].
  @override
  bool canReflect(Object o) => _canReflect(dm.reflect(o));

  /// Returns a mirror of the given object [reflectee]
  @override
  rm.InstanceMirror reflect(Object o) {
    dm.InstanceMirror mirror = dm.reflect(o);
    if (_canReflect(mirror)) return wrapInstanceMirror(mirror, this);
    throw new NoSuchCapabilityError(
        "Attempt to reflect on class '${o.runtimeType}' without capability");
  }

  bool get _supportsType {
    return capabilities
        .any((ReflectCapability capability) => capability is TypeCapability);
  }

  bool _canReflectType(dm.ClassMirror mirror) {
    return _supportsType &&
        _supportedClasses.contains(mirror.originalDeclaration);
  }

  @override
  bool canReflectType(Type type) {
    dm.TypeMirror typeMirror = dm.reflectType(type);
    if (typeMirror is dm.ClassMirror) {
      return _canReflectType(typeMirror);
    } else {
      throw new UnimplementedError("Checking reflection support on a "
          "currently unsupported kind of type: $typeMirror");
    }
  }

  @override
  rm.TypeMirror reflectType(Type type) {
    if (!_supportsType) {
      throw new NoSuchCapabilityError(
          "Reflecting on type $type without capability");
    }
    dm.TypeMirror typeMirror = dm.reflectType(type);
    if (typeMirror is dm.ClassMirror) {
      return wrapClassMirrorIfSupported(typeMirror, this);
    } else {
      throw new UnimplementedError("Checking reflection support on a "
          "currently unsupported kind of type: $typeMirror");
    }
  }

  bool get _supportsLibraries {
    return capabilities
        .any((ReflectCapability capability) => capability == libraryCapability);
  }

  @override
  rm.LibraryMirror findLibrary(String libraryName) {
    if (!_supportsLibraries) {
      throw new NoSuchCapabilityError(
          "Searching for library '$libraryName'. LibraryMirrors are not "
          "supported by this reflector. Try adding 'libraryCapability'");
    }
    Symbol librarySymbol = new Symbol(libraryName);
    return new _LibraryMirrorImpl(
        dm.currentMirrorSystem().findLibrary(librarySymbol), this);
  }

  @override
  Map<Uri, rm.LibraryMirror> get libraries {
    if (!_supportsLibraries) {
      throw new NoSuchCapabilityError(
          "Trying to obtain a library mirror without capability. Try adding "
          "'libraryCapability'");
    }
    Map<Uri, dm.LibraryMirror> libs = dm.currentMirrorSystem().libraries;
    return new Map<Uri, rm.LibraryMirror>.fromIterable(libs.keys,
        key: (k) => k, value: (k) => new _LibraryMirrorImpl(libs[k], this));
  }

  @override
  Iterable<rm.ClassMirror> get annotatedClasses {
    return _supportedClasses.map((dm.ClassMirror classMirror) {
      return wrapClassMirrorIfSupported(classMirror, this);
    });
  }

  /// Returns the set of [dm.ClassMirror]s corresponding to the classes
  /// (and associated instances thereof) which must receive the reflection
  /// support that this [ReflectableImpl] specifies. It includes the
  /// classes which carry an instance of this [ReflectableImpl] as metadata
  /// directly, plus the classes which are included because they matched a
  /// [GlobalQuantifyCapability] or a [GlobalQuantifyMetaCapability] carrying
  /// this [ReflectableImpl]. Finally, this set of classes is downward-closed
  /// (every subtype of each member of the set is added) if there is a
  /// `subtypeQuantifyCapability` in `capabilities`. In short, a given class
  /// C is supported by this [ReflectableImpl] iff
  /// `this._supportedClasses.contains(m.originalDeclaration)`, where `m`
  /// is a [dm.ClassMirror] on C.
  Set<dm.ClassMirror> get _supportedClasses {
    // TODO(sigurdm) implement: This cache will break with deferred loading.
    return _supportedClassesCache.putIfAbsent(this, () {
      Set<dm.ClassMirror> result = new Set<dm.ClassMirror>();
      List<RegExp> globalPatterns = new List<RegExp>();
      Set<Type> globalMetadataClasses = new Set<Type>();

      // Gather all global quantifications that are annotations of
      // imports of 'reflectable.reflectable'.
      for (dm.LibraryMirror library
          in dm.currentMirrorSystem().libraries.values) {
        for (dm.LibraryDependencyMirror dependency
            in library.libraryDependencies) {
          if (dependency.isImport &&
              dependency.targetLibrary.qualifiedName ==
                  reflectableLibrarySymbol) {
            for (dm.InstanceMirror metadatumMirror in dependency.metadata) {
              Object metadatum = metadatumMirror.reflectee;
              if (metadatum is GlobalQuantifyCapability &&
                  metadatum.reflector == this) {
                globalPatterns.add(new RegExp(metadatum.classNamePattern));
              }
              if (metadatum is GlobalQuantifyMetaCapability &&
                  metadatum.reflector == this) {
                globalMetadataClasses.add(metadatum.metadataType);
              }
            }
          }
        }
      }

      // Find all classes that are annotated, as well as the ones that match
      // a global quantification.
      for (dm.LibraryMirror library
          in dm.currentMirrorSystem().libraries.values) {
        declarationLoop: for (dm.DeclarationMirror declaration
            in library.declarations.values) {
          if (declaration is dm.ClassMirror) {
            for (dm.InstanceMirror metadatum in declaration.metadata) {
              if (metadatum.reflectee == this ||
                  globalMetadataClasses
                      .contains(metadatum.reflectee.runtimeType)) {
                result.add(declaration.originalDeclaration);
                continue declarationLoop;
              }
            }
            String qualifiedName =
                dm.MirrorSystem.getName(declaration.qualifiedName);
            for (RegExp pattern in globalPatterns) {
              if (pattern.hasMatch(qualifiedName)) {
                result.add(declaration.originalDeclaration);
                continue declarationLoop;
              }
            }
          }
        }
      }

      // If subtype quantification has been requested, extend `result` to
      // be downwards closed.
      if (capabilities
          .any((capability) => capability == subtypeQuantifyCapability)) {
        // At least one [SubtypeQuantifyCapability] occurs, so we must
        // include all subtypes of the supported types.
        Set<dm.ClassMirror> subtypes = new Set<dm.ClassMirror>();
        for (dm.LibraryMirror library
            in dm.currentMirrorSystem().libraries.values) {
          for (dm.DeclarationMirror declaration
              in library.declarations.values) {
            if (declaration is dm.ClassMirror) {
              if (result.contains(declaration.originalDeclaration)) continue;
              for (dm.ClassMirror classMirror in result) {
                if (declaration.isSubtypeOf(classMirror)) {
                  subtypes.add(declaration.originalDeclaration);
                  break;
                }
              }
            }
          }
        }
        result.addAll(subtypes);
      }

      // Perform a fixed point iteration to extend the `result` set of classes
      // to include the transitive closure of certain related classes: The
      // ones that are used as type annotations for variables and in method
      // signatures, and the ones which are superclasses of already included
      // classes (in both cases: when suitable capabilities are present).
      // This comment pertains to the following declarations and the long `if`.

      bool annotatedTypesRequested = impliesTypes(capabilities);
      bool upwardsClosureRequested = impliesUpwardsClosure(capabilities);

      List<dm.ClassMirror> upwardsClosureBounds =
          extractUpwardsClosureBounds(capabilities);
      Set<dm.ClassMirror> workingSet = new Set<dm.ClassMirror>.from(result);

      bool includedByUpwardsClosure(dm.ClassMirror classMirror) {
        if (upwardsClosureBounds.isEmpty) return true;
        return upwardsClosureBounds
            .any((dm.ClassMirror bound) => classMirror.isSubclassOf(bound));
      }

      // Overall approach in this fixed point iteration: The set `result`
      // is the set of currently included classes and `workingSet` is the
      // subset thereof for which there may exist immediate successors
      // (type annotations or superclass) which need to be added. In each
      // iteration the set `additionalClasses` starts out empty and the
      // immediate successors of classes in `workingSet` are added to
      // `additionalClasses`. At the end of each iteration, `additionalClasses`
      // becomes the new `workingSet` and the old `workingSet` is added to
      // `result`, i.e., we can terminate when `workingSet` is empty.
      while (workingSet.isNotEmpty) {
        Set<dm.ClassMirror> additionalClasses = new Set<dm.ClassMirror>();

        void addClass(dm.TypeMirror typeMirror) {
          dm.TypeMirror original = typeMirror.originalDeclaration;
          if (original is dm.ClassMirror && !result.contains(original)) {
            additionalClasses.add(original);
          }
        }

        for (dm.ClassMirror workingClass in workingSet) {
          if (annotatedTypesRequested) {
            for (dm.DeclarationMirror declaration
                in workingClass.declarations.values) {
              if (declaration is dm.VariableMirror) {
                addClass(declaration.type);
              }
              if (declaration is dm.MethodMirror) {
                for (dm.ParameterMirror parameter in declaration.parameters) {
                  addClass(parameter.type);
                }
                addClass(declaration.returnType);
              }
            }
          }

          if (upwardsClosureRequested) {
            // Add the superclass, whether or not it is a mixin application.
            dm.ClassMirror superclass = workingClass.superclass;
            if (superclass != null) {
              if (includedByUpwardsClosure(superclass)) {
                addClass(superclass);
                // If it is a mixin application, try to add the origin (the
                // class that provided the mixin) as well.
                // TODO(eernst) clarify: Consider whether we should do this!
                // Pro: If a mixin application is included then the natural
                //   consequence would be that so is its origin.
                // Con: For overall space frugality, we should not include
                //   the origin unless it is explicitly requested.
                if (superclass.mixin != superclass &&
                    includedByUpwardsClosure(superclass.mixin)) {
                  addClass(superclass.mixin);
                }
              }
            }
          } else {
            // Add mixin-applications as long as the extended class and
            // each mixin is included.
            dm.ClassMirror superclass = workingClass.superclass;
            while (superclass != null && superclass.mixin != superclass) {
              if (result.contains(superclass.mixin.originalDeclaration)) {
                addClass(superclass);
              }
              superclass = superclass.superclass;
            }
          }
        }
        result.addAll(additionalClasses);
        workingSet = additionalClasses;
      }

      return result;
    });
  }

  static Map<ReflectableImpl, Set<dm.ClassMirror>> _supportedClassesCache =
      new Map<ReflectableImpl, Set<dm.ClassMirror>>();

  /// Returns `true` iff this [ReflectableImpl] contains an
  /// [ApiReflectCapability] which satisfies the given [predicate], i.e.,
  /// if the corresponding capability to do something has been granted
  /// for a class that carries this [ReflectableImpl] as metadata, and to
  /// the instances of such a class.
  bool hasCapability(bool predicate(ApiReflectCapability capability)) {
    return capabilities.any((ReflectCapability capability) =>
        capability is ApiReflectCapability && predicate(capability));
  }
}
