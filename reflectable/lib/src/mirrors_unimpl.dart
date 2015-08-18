// Copyright (c) 2015, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.mirrors_unimpl;

import 'dart:collection' show UnmodifiableMapView, UnmodifiableListView;

import '../capability.dart';
import '../mirrors.dart';
import '../reflectable.dart';
import 'encoding_constants.dart' as constants;
import 'reflectable_base.dart';

bool get isTransformed => true;

// Mirror classes with default implementations of all methods, to be used as
// superclasses of transformer generated static mirror classes.  They serve to
// ensure that the static mirror classes always implement all methods, such that
// they throw an exception at runtime, rather than causing an error at compile
// time, which is the required behavior for static mirrors when they are used
// in ways that are not covered by the specified capabilities.
//
// Each of these classes implements the corresponding class in
// `package:reflectable/mirrors.dart`, and they replicate the internal
// implements `structure in package:reflectable/mirrors.dart` using `extends`
// and `with` clauses, such that the (un)implementation is inherited rather than
// replicated wherever possible.

_unsupported() => throw new UnimplementedError();

/// Invokes a getter on an object.
typedef Object _InvokerOfGetter(Object instance);

/// Invokes a setter on an object.
typedef Object _InvokerOfSetter(Object instance, Object value);

/// Invokes a static getter.
typedef Object _StaticGetter();

/// Invokes a setter on an object.
typedef Object _StaticSetter(Object value);

/// The data backing a reflector.
class ReflectorData {
  /// List of class mirrors, one class mirror for each class that is
  /// supported by reflection as specified by the reflector backed up
  /// by this [ReflectorData].
  final List<ClassMirror> classMirrors;

  /// Repository of method mirrors used (via indices into this list) by
  /// the [classMirrors] to describe the behavior of the mirrored
  /// class and its instances, and of variable mirrors used to describe
  /// their state. From the behavioral point of view there are no fields,
  /// but each of them gives rise to a getter and possibly a setter (whose
  /// `isSynthetic` is true). The implicit getters/setters are not stored
  /// in this list, but they can be reconstructed based on the variable
  /// mirrors describing the fields. From the program structure point of
  /// view (used for `declarations`), the method mirrors and the field
  /// mirrors must both be included directly. Hence, both points of view
  /// require a little bit of processing, but in return we avoid some
  /// redundancy in the stored information.
  final List<DeclarationMirror> memberMirrors;

  /// Repository of parameter mirrors used (via indices into this list) by
  /// the [memberMirrors] to describe the parameters of methods
  final List<ParameterMirror> parameterMirrors;

  /// List of [Type]s used to select class mirrors: If M is a class
  /// mirror in [classMirrors] at index `i`, the mirrored class (and
  /// hence the runtime type of the mirrored instances) is found in
  /// `types[i]`.
  final List<Type> types;

  /// Map from getter names to closures accepting an instance and returning
  /// the result of invoking the getter with that name on that instance.
  final Map<String, _InvokerOfGetter> getters;

  /// Map from setter names to closures accepting an instance and a new value,
  /// invoking the setter of that name on that instance, and returning its
  /// return value.
  final Map<String, _InvokerOfSetter> setters;

  Map<Type, ClassMirror> _typeToClassMirrorCache;

  ReflectorData(this.classMirrors, this.memberMirrors, this.parameterMirrors,
      this.types, this.getters, this.setters);

  /// Returns a class-mirror for the given [type].
  ///
  /// Returns `null` if the given class is not marked for reflection.
  ClassMirror classMirrorForType(Type type) {
    if (_typeToClassMirrorCache == null) {
      _typeToClassMirrorCache = new Map.fromIterables(types, classMirrors);
    }
    return _typeToClassMirrorCache[type];
  }
}

/// This mapping contains the mirror-data for each reflector.
/// It will be initialized in the generated code.
Map<Reflectable, ReflectorData> data =
    throw new StateError("Reflectable has not been initialized. "
        "Did you forget to add the main file to the "
        "reflectable transformer's entry_points in pubspec.yaml?");

abstract class _DataCaching {
  // TODO(eernst) clarify: When we have some substantial pieces of code using
  // reflectable, perform some experiments to detect how useful it is to have
  // this kind of caching.

  ReflectorData _dataCache;
  ReflectableImpl get _reflector;

  ReflectorData get _data {
    if (_dataCache == null) {
      _dataCache = data[_reflector];
    }
    return _dataCache;
  }
}

class _InstanceMirrorImpl extends _DataCaching implements InstanceMirror {
  final ReflectableImpl _reflector;
  final Object reflectee;

  _InstanceMirrorImpl(this.reflectee, this._reflector) {
    _type = _data.classMirrorForType(reflectee.runtimeType);
    if (_type == null) {
      throw new NoSuchCapabilityError(
          "Reflecting on un-marked type ${reflectee.runtimeType}");
    }
  }

  ClassMirror _type;

  ClassMirror get type => _type;

  Object invoke(String methodName, List<Object> positionalArguments,
      [Map<Symbol, Object> namedArguments]) {
    Function methodTearer = _data.getters[methodName];
    if (methodTearer != null) {
      return Function.apply(
          methodTearer(reflectee), positionalArguments, namedArguments);
    }
    throw new NoSuchInvokeCapabilityError(
        reflectee, methodName, positionalArguments, namedArguments);
  }

  bool get hasReflectee => true;

  bool operator ==(other) {
    return other is _InstanceMirrorImpl &&
        other._reflector == _reflector &&
        other.reflectee == reflectee;
  }

  int get hashCode => reflectee.hashCode ^ _reflector.hashCode;

  delegate(Invocation invocation) => _unsupported();

  @override
  Object invokeGetter(String getterName) {
    Function getter = _data.getters[getterName];
    if (getter != null) {
      return getter(reflectee);
    }
    throw new NoSuchInvokeCapabilityError(reflectee, getterName, [], {});
  }

  @override
  Object invokeSetter(String setterName, Object value) {
    if (setterName.substring(setterName.length - 1) != "=") {
      setterName += "=";
    }
    Function setter = _data.setters[setterName];
    if (setter != null) {
      return setter(reflectee, value);
    }
    throw new NoSuchInvokeCapabilityError(reflectee, setterName, [value], {});
  }
}

int _variableToImplicitAccessorAttributes(VariableMirror variableMirror) {
  int attributes = 0;
  if (variableMirror.isPrivate) attributes |= constants.privateAttribute;
  if (variableMirror.isStatic) attributes |= constants.staticAttribute;
  attributes |= constants.syntheticAttribute;
  return attributes;
}

MethodMirror _variableToGetterMirror(VariableMirrorImpl variableMirror) {
  int descriptor = constants.getter;
  descriptor |= _variableToImplicitAccessorAttributes(variableMirror);
  // TODO(eernst) clarify: Make sure it is the right `ownerIndex`: Write a test
  // that compares owners in pre/post-transform code.
  return new MethodMirrorImpl(variableMirror.simpleName, descriptor,
      variableMirror._ownerIndex, [], variableMirror._reflector, []);
}

// TODO(eernst) implement: Make this method take an `index` parameter which
// will be the index of the returned `MethodMirror`, such that the enclosed
// parameter mirror can get the right ownerIndex.
MethodMirror _variableToSetterMirror(VariableMirrorImpl variableMirror) {
  int descriptor = constants.setter | constants.syntheticAttribute;
  descriptor |= _variableToImplicitAccessorAttributes(variableMirror);
  int parameterDescriptor = constants.parameter | constants.syntheticAttribute;
  String name = variableMirror.simpleName + "=";
  return new MethodMirrorImpl(
      name,
      descriptor,
      variableMirror._ownerIndex,
      [
        // TODO(eernst) clarify: Make sure it is the right `ownerIndex`: Write a
        // test that compares owners in pre/post-transform code.
        new ParameterMirrorImpl(
            name,
            parameterDescriptor,
            variableMirror._ownerIndex,
            variableMirror._reflector,
            -1,
            variableMirror.metadata,
            null)
      ],
      variableMirror._reflector,
      []);
}

class ClassMirrorImpl extends _DataCaching implements ClassMirror {
  /// The reflector which represents the mirror system that this
  /// mirror belongs to.
  final ReflectableImpl _reflector;

  /// The index of this mirror in the [ReflectorData.classMirrors] table.
  /// Also this is the index of the Type of the reflected class in
  /// [ReflectorData.types].
  final int _classIndex;

  /// A list of the indices in [ReflectorData.memberMirrors] of the
  /// declarations of the reflected class. This includes method mirrors
  /// and variable mirrors and it directly corresponds to `declarations`.
  /// Exception: When the given `_reflector.capabilities` do not support
  /// the operation `declarations`, this will be `<int>[-1]`. It is enough
  /// to check that the list is non-empty and first element is -1 to
  /// detect this situation, because -1 will otherwise never occur.
  final List<int> _declarationIndices;

  /// A list of the indices in [ReflectorData.memberMirrors] of the
  /// instance members of the reflected class, except that it includes
  /// variable mirrors describing fields which must be converted to
  /// implicit getters and possibly implicit setters in order to
  /// obtain the correct result for `instanceMembers`.
  final List<int> _instanceMemberIndices;

  /// The index of the mirror of the superclass in the
  /// [ReflectorData.classMirrors] table.
  final int _superclassIndex;

  final String simpleName;
  final String qualifiedName;
  final List<Object> _metadata;
  final Map<String, _StaticGetter> getters;
  final Map<String, _StaticSetter> setters;
  final Map<String, Function> constructors;

  ClassMirrorImpl(
      this.simpleName,
      this.qualifiedName,
      this._classIndex,
      this._reflector,
      this._declarationIndices,
      this._instanceMemberIndices,
      this._superclassIndex,
      this.getters,
      this.setters,
      this.constructors,
      metadata)
      : _metadata =
            (metadata == null) ? null : new UnmodifiableListView(metadata);

  ClassMirror get superclass {
    if (_superclassIndex == null) return null;
    if (_superclassIndex == -1) {
      throw new NoSuchCapabilityError(
          "Requesting mirror on un-marked class, superclass of $simpleName");
    }
    return _data.classMirrors[_superclassIndex];
  }

  List<ClassMirror> get superinterfaces => _unsupported();

  bool get isAbstract => _unsupported();

  Map<String, DeclarationMirror> _declarations;

  Map<String, DeclarationMirror> get declarations {
    if (_declarations == null) {
      Map<String, DeclarationMirror> result =
          new Map<String, DeclarationMirror>();
      for (int declarationIndex in _declarationIndices) {
        // We encode a missing `declarations` capability as an index with
        // the value -1. Note that `_declarations` will not be initialized
        // and hence we will come here repeatedly if that is the case; however,
        // performing operations for which there is no capability need not
        // have stellar performance, it is almost always a bug to do that.
        if (declarationIndex == -1) {
          throw new NoSuchCapabilityError(
              "Requesting declarations without capability");
        }
        DeclarationMirror declarationMirror =
            _data.memberMirrors[declarationIndex];
        result[declarationMirror.simpleName] = declarationMirror;
      }
      _declarations =
          new UnmodifiableMapView<String, DeclarationMirror>(result);
    }
    return _declarations;
  }

  Map<String, MethodMirror> _instanceMembers;

  Map<String, MethodMirror> get instanceMembers {
    if (_instanceMembers == null) {
      Map<String, MethodMirror> result = new Map<String, MethodMirror>();
      for (int instanceMemberIndex in _instanceMemberIndices) {
        DeclarationMirror declarationMirror =
            _data.memberMirrors[instanceMemberIndex];
        if (declarationMirror is MethodMirror) {
          result[declarationMirror.simpleName] = declarationMirror;
        } else {
          assert(declarationMirror is VariableMirror);
          // Need declaration because `assert` provides no type propagation.
          VariableMirror variableMirror = declarationMirror;
          result[variableMirror.simpleName] =
              _variableToGetterMirror(variableMirror);
          if (!variableMirror.isFinal) {
            result[variableMirror.simpleName + "="] =
                _variableToSetterMirror(variableMirror);
          }
        }
      }
      _instanceMembers = new UnmodifiableMapView<String, MethodMirror>(result);
    }
    return _instanceMembers;
  }

  Map<String, MethodMirror> get staticMembers => _unsupported();

  ClassMirror get mixin => _unsupported();

  Object newInstance(String constructorName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    return Function.apply(
        constructors["$constructorName"], positionalArguments, namedArguments);
  }

  bool isSubclassOf(ClassMirror other) {
    if (other is FunctionTypeMirror) {
      return false;
    }
    if (other is ClassMirror && other.reflectedType == reflectedType) {
      return true;
    } else if (superclass == null) {
      return false;
    } else {
      return superclass.isSubclassOf(other);
    }
  }

  @override
  bool get hasReflectedType => true;

  @override
  Object invoke(String memberName, List positionalArguments,
      [Map<Symbol, dynamic> namedArguments]) {
    _StaticGetter getter = getters[memberName];
    if (getter == null) {
      throw new NoSuchInvokeCapabilityError(
          reflectedType, memberName, positionalArguments, namedArguments);
    }
    return Function.apply(
        getters[memberName](), positionalArguments, namedArguments);
  }

  @override
  Object invokeGetter(String getterName) {
    _StaticGetter getter = getters[getterName];
    if (getter == null) {
      throw new NoSuchInvokeCapabilityError(reflectedType, getterName, [], {});
    }
    return getter();
  }

  @override
  Object invokeSetter(String setterName, Object value) {
    _StaticSetter setter = setters[setterName];
    if (setter == null) {
      throw new NoSuchInvokeCapabilityError(
          reflectedType, setterName, [value], {});
    }
    return setter(value);
  }

  // TODO(eernst) feature: Implement `isAssignableTo`.
  @override
  bool isAssignableTo(TypeMirror other) => _unsupported();

  // TODO(eernst) feature: Implement `isOriginalDeclaration`.
  @override
  bool get isOriginalDeclaration => _unsupported();

  // For now we only support reflection on public classes.
  @override
  bool get isPrivate => false;

  // TODO(eernst) feature: Implement `isSubTypeOf`.
  @override
  bool isSubtypeOf(TypeMirror other) => _unsupported();

  // Classes are always toplevel.
  @override
  bool get isTopLevel => true;

  // It is allowed to return null.
  @override
  SourceLocation get location => null;

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      throw new NoSuchCapabilityError(
          "Requesting metadata of $reflectedType without capability");
    }
    return _metadata;
  }

  @override
  TypeMirror get originalDeclaration => _unsupported();

  @override
  DeclarationMirror get owner => _unsupported();

  @override
  Type get reflectedType => _data.types[_classIndex];

  @override
  List<TypeMirror> get typeArguments => _unsupported();

  @override
  List<TypeVariableMirror> get typeVariables => _unsupported();

  @override
  Function invoker(String memberName) {
    Function getter = _data.getters[memberName];
    if (getter == null) {
      throw new NoSuchInvokeCapabilityError(reflectedType, memberName, [], {});
    }
    return getter;
  }

  String toString() => "ClassMirrorImpl($qualifiedName)";

  // Because we take care to only ever create one instance for each
  // type/reflector-combination we can rely on the default `hashCode` and `==`
  // operations.
}

class MethodMirrorImpl extends _DataCaching implements MethodMirror {
  /// An encoding of the attributes and kind of this mirror.
  final int _descriptor;

  /// The name of this method. Setters names will end in '='.
  final String _name;

  /// The index of the [ClassMirror] of the owner of this method,
  final int _ownerIndex;

  /// The indices of the [ParameterMirror]s describing the formal parameters
  /// of this method.
  final List<int> _parameterIndices;

  /// The [Reflectable] associated with this mirror.
  final ReflectableImpl _reflector;

  /// A cache of the metadata of the mirrored method. The empty list means
  /// no metadata, null means that [_reflector] does not have
  /// [metadataCapability].
  final List<Object> _metadata;

  MethodMirrorImpl(this._name, this._descriptor, this._ownerIndex,
      this._parameterIndices, this._reflector, List<Object> metadata)
      : _metadata =
            (metadata == null) ? null : new UnmodifiableListView(metadata);

  int get kind => constants.kindFromEncoding(_descriptor);

  ClassMirror get owner => _data.classMirrors[_ownerIndex];

  @override
  String get constructorName => _name;

  @override
  bool get isAbstract => (_descriptor & constants.abstractAttribute != 0);

  @override
  bool get isConstConstructor => (_descriptor & constants.constAttribute != 0);

  @override
  bool get isConstructor => isFactoryConstructor || isGenerativeConstructor;

  @override
  bool get isFactoryConstructor => kind == constants.factoryConstructor;

  @override
  bool get isGenerativeConstructor => kind == constants.generativeConstructor;

  @override
  bool get isGetter => kind == constants.getter;

  @override
  bool get isOperator => isRegularMethod &&
      ["+", "-", "*", "/", "[", "<", ">", "=", "~", "%"].contains(_name[0]);

  @override
  bool get isPrivate => (_descriptor & constants.privateAttribute != 0);

  @override
  bool get isRedirectingConstructor =>
      (_descriptor & constants.redirectingConstructorAttribute != 0);

  @override
  bool get isRegularMethod => kind == constants.method;

  @override
  bool get isSetter => kind == constants.setter;

  @override
  bool get isStatic => (_descriptor & constants.staticAttribute != 0);

  @override
  bool get isSynthetic => (_descriptor & constants.syntheticAttribute != 0);

  @override
  bool get isTopLevel => owner is LibraryMirror;

  // It is allowed to return null.
  @override
  SourceLocation get location => null;

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      throw new NoSuchCapabilityError(
          "Requesting metadata of method $simpleName without capability");
    }
    return _metadata;
  }

  @override
  List<ParameterMirror> get parameters {
    return _parameterIndices
        .map((int parameterIndex) => _data.parameterMirrors[parameterIndex])
        .toList();
  }

  @override
  String get qualifiedName => "${owner.qualifiedName}.$_name";

  // TODO(sigurdm) feature: suport `returnType`.
  @override
  TypeMirror get returnType => throw new UnimplementedError();

  @override
  String get simpleName => isConstructor
      ? (_name == '' ? "${owner.simpleName}" : "${owner.simpleName}.$_name")
      : _name;

  @override
  String get source => null;

  @override
  String toString() => "MethodMirror($_name)";
}

abstract class VariableMirrorBase extends _DataCaching
    implements VariableMirror {
  final String _name;
  final int _descriptor;
  final int _ownerIndex;
  final ReflectableImpl _reflector;
  final _classMirrorIndex;
  final List<Object> _metadata;

  VariableMirrorBase(this._name, this._descriptor, this._ownerIndex,
      this._reflector, this._classMirrorIndex, List<Object> metadata)
      : _metadata =
            (metadata == null) ? null : new UnmodifiableListView(metadata);

  int get kind => constants.kindFromEncoding(_descriptor);

  @override
  bool get isPrivate => (_descriptor & constants.privateAttribute != 0);

  @override
  bool get isTopLevel => owner is LibraryMirror;

  @override
  bool get isFinal => (_descriptor & constants.finalAttribute != 0);

  bool get _isDynamic => (_descriptor & constants.dynamicAttribute != 0);

  bool get _isClassType => (_descriptor & constants.classTypeAttribute != 0);

  // It is allowed to return null.
  @override
  SourceLocation get location => null;

  @override
  List<Object> get metadata {
    if (_metadata == null) {
      throw new NoSuchCapabilityError(
          "Requesting metadata of field $simpleName without capability");
    }
    return _metadata;
  }

  @override
  bool operator ==(other) => _unsupported();

  @override
  int get hashCode => _unsupported();

  @override
  String get simpleName => _name;

  @override
  TypeMirror get type {
    if (_isDynamic) return new DynamicMirrorImpl();
    if (_isClassType) {
      if (_classMirrorIndex == -1) {
        throw new NoSuchCapabilityError(
            "Attempt to get class mirror for un-marked class (type of $_name)");
      }
      return _data.classMirrors[_classMirrorIndex];
    }
    return _unsupported();
  }
}

class VariableMirrorImpl extends VariableMirrorBase {
  @override
  ClassMirror get owner => _data.classMirrors[_ownerIndex];

  @override
  String get qualifiedName => "${owner.qualifiedName}.$_name";

  @override
  bool get isStatic => (_descriptor & constants.staticAttribute != 0);

  @override
  bool get isConst => (_descriptor & constants.constAttribute != 0);

  VariableMirrorImpl(String name, int descriptor, int ownerIndex,
      ReflectableImpl reflectable, int classMirrorIndex, List<Object> metadata)
      : super(name, descriptor, ownerIndex, reflectable, classMirrorIndex,
            metadata);
}

class ParameterMirrorImpl extends VariableMirrorBase
    implements ParameterMirror {
  @override
  final defaultValue;

  @override
  bool get isStatic => (_descriptor & constants.staticAttribute != 0);

  @override
  bool get isConst => (_descriptor & constants.constAttribute != 0);

  @override
  bool get hasDefaultValue =>
      (_descriptor & constants.hasDefaultValueAttribute != 0);

  @override
  bool get isOptional => (_descriptor & constants.optionalAttribute != 0);

  @override
  bool get isNamed => (_descriptor & constants.namedAttribute != 0);

  // TODO(eernst) clarify: A parameter cannot be accessed using dot
  // notation, and hence it has no qualified name. So is the following
  // behavior correct?
  @override
  String get qualifiedName {
    throw new NoSuchCapabilityError(
        "Attempting to get the `qualifiedName` of the parameter $_name.");
  }

  @override
  MethodMirror get owner => _data.memberMirrors[_ownerIndex];

  ParameterMirrorImpl(
      String name,
      int descriptor,
      int ownerIndex,
      ReflectableImpl reflectable,
      classMirrorIndex,
      List<Object> metadata,
      this.defaultValue)
      : super(name, descriptor, ownerIndex, reflectable, classMirrorIndex,
            metadata);
}

class DynamicMirrorImpl implements TypeMirror {
  @override
  bool get isPrivate => false;

  @override
  bool get isTopLevel => true;

  // TODO(eernst) implement: test what 'dart:mirrors' does, then do the same.
  @override
  bool get isOriginalDeclaration => true;

  @override
  bool get hasReflectedType => true;

  @override
  Type get reflectedType => dynamic;

  @override
  String get simpleName => "dynamic";

  // TODO(eernst) implement: do as in 'dart:mirrors'.
  @override
  List<TypeVariableMirror> get typeVariables => <TypeVariableMirror>[];

  @override
  List<TypeMirror> get typeArguments => <TypeMirror>[];

  // TODO(eernst) implement: do as in 'dart:mirrors'.
  @override
  TypeMirror get originalDeclaration => null;

  // It is allowed to return null.
  @override
  SourceLocation get location => null;

  @override
  bool isSubtypeOf(TypeMirror other) => true;

  @override
  bool isAssignableTo(TypeMirror other) => true;

  // TODO(eernst) implement: do as 'dart:mirrors' does.
  @override
  DeclarationMirror get owner => null;

  @override
  String get qualifiedName => simpleName;

  @override
  List<Object> get metadata => <Object>[];
}

abstract class ReflectableImpl extends ReflectableBase
    implements ReflectableInterface {
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

  @override
  InstanceMirror reflect(Object reflectee) {
    return new _InstanceMirrorImpl(reflectee, this);
  }

  @override
  bool canReflect(Object reflectee) {
    return data[this].classMirrorForType(reflectee.runtimeType) != null;
  }

  @override
  ClassMirror reflectType(Type type) {
    ClassMirror result = data[this].classMirrorForType(type);
    if (result == null) {
      throw new NoSuchCapabilityError(
          "Reflecting on type $type that is not reflector-marked.");
    }
    return result;
  }

  @override
  bool canReflectType(Type type) {
    return data[this].classMirrorForType(type) != null;
  }

  @override
  LibraryMirror findLibrary(String library) => _unsupported();

  @override
  Map<Uri, LibraryMirror> get libraries => _unsupported();

  @override
  Iterable<ClassMirror> get annotatedClasses {
    return new UnmodifiableListView<ClassMirror>(data[this].classMirrors);
  }
}
