// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

import 'dart:math' as math;

import 'package:front_end/src/fasta/fasta_codes.dart';
import 'package:kernel/ast.dart'
    show
        BottomType,
        Class,
        DartType,
        DynamicType,
        FunctionType,
        InterfaceType,
        InvalidType,
        Library,
        NamedType,
        NeverType,
        Nullability,
        TypeParameter,
        TypeParameterType,
        Variance,
        VoidType;

import 'package:kernel/type_algebra.dart';

import 'package:kernel/type_environment.dart';

import 'package:kernel/src/future_or.dart';

import 'type_schema.dart' show UnknownType;

import '../problems.dart';

abstract class StandardBounds {
  Class get functionClass;
  Class get futureClass;
  Class get futureOrClass;
  Class get objectClass;
  InterfaceType get nullType;
  InterfaceType get objectLegacyRawType;
  InterfaceType get objectNonNullableRawType;
  InterfaceType get functionLegacyRawType;
  InterfaceType functionRawType(Nullability nullability);
  InterfaceType objectRawType(Nullability nullability);

  bool isSubtypeOf(DartType subtype, DartType supertype, SubtypeCheckMode mode);

  bool areMutualSubtypes(DartType s, DartType t, SubtypeCheckMode mode);

  InterfaceType getLegacyLeastUpperBound(
      InterfaceType type1, InterfaceType type2, Library clientLibrary);

  /// Checks if [type] satisfies the TOP predicate.
  ///
  /// For the definition of TOP see the following:
  /// https://github.com/dart-lang/language/blob/master/resources/type-system/upper-lower-bounds.md#helper-predicates
  bool _isTop(DartType type) {
    if (type is InvalidType) return false;

    // TOP(dynamic) is true.
    if (type is DynamicType) return true;

    // TOP(void) is true.
    if (type is VoidType) return true;

    // TOP(T?) is true iff TOP(T) or OBJECT(T).
    // TOP(T*) is true iff TOP(T) or OBJECT(T).
    if (type.nullability == Nullability.nullable ||
        type.nullability == Nullability.legacy) {
      DartType nonNullableType = type.withNullability(Nullability.nonNullable);
      assert(type != nonNullableType);
      return _isTop(nonNullableType) || _isObject(nonNullableType);
    }

    // TOP(FutureOr<T>) is TOP(T).
    if (type is InterfaceType && type.classNode == futureOrClass) {
      return _isTop(type.typeArguments.single);
    }

    return false;
  }

  /// Checks if [type] satisfies the OBJECT predicate.
  ///
  /// For the definition of OBJECT see the following:
  /// https://github.com/dart-lang/language/blob/master/resources/type-system/upper-lower-bounds.md#helper-predicates
  bool _isObject(DartType type) {
    if (type is InvalidType) return false;

    // OBJECT(Object) is true.
    if (type is InterfaceType &&
        type.classNode == objectClass &&
        type.nullability == Nullability.nonNullable) {
      return true;
    }

    // OBJECT(FutureOr<T>) is OBJECT(T).
    if (type is InterfaceType &&
        type.classNode == futureOrClass &&
        type.nullability == Nullability.nonNullable) {
      return _isObject(type.typeArguments.single);
    }

    return false;
  }

  /// Checks if [type] satisfies the BOTTOM predicate.
  ///
  /// For the definition of BOTTOM see the following:
  /// https://github.com/dart-lang/language/blob/master/resources/type-system/upper-lower-bounds.md#helper-predicates
  bool _isBottom(DartType type) {
    if (type is InvalidType) return false;

    // BOTTOM(Never) is true.
    if (type is NeverType && type.nullability == Nullability.nonNullable) {
      return true;
    }

    // BOTTOM(X&T) is true iff BOTTOM(T).
    if (type is TypeParameterType &&
        type.promotedBound != null &&
        type.isPotentiallyNonNullable) {
      return _isBottom(type.promotedBound);
    }

    // BOTTOM(X extends T) is true iff BOTTOM(T).
    if (type is TypeParameterType && type.isPotentiallyNonNullable) {
      assert(type.promotedBound == null);
      return _isBottom(type.parameter.bound);
    }

    if (type is BottomType) return true;

    return false;
  }

  /// Checks if [type] satisfies the NULL predicate.
  ///
  /// For the definition of NULL see the following:
  /// https://github.com/dart-lang/language/blob/master/resources/type-system/upper-lower-bounds.md#helper-predicates
  bool _isNull(DartType type) {
    if (type is InvalidType) return false;

    // NULL(Null) is true.
    if (type == nullType) return true;

    // NULL(T?) is true iff NULL(T) or BOTTOM(T).
    // NULL(T*) is true iff NULL(T) or BOTTOM(T).
    if (type.nullability == Nullability.nullable ||
        type.nullability == Nullability.legacy) {
      DartType nonNullableType = type.withNullability(Nullability.nonNullable);
      return _isBottom(nonNullableType);
    }

    return false;
  }

  /// Checks the value of the MORETOP predicate for [s] and [t].
  ///
  /// For the definition of MORETOP see the following:
  /// https://github.com/dart-lang/language/blob/master/resources/type-system/upper-lower-bounds.md#helper-predicates
  bool moretop(DartType s, DartType t) {
    assert(_isTop(s) || _isObject(s));
    assert(_isTop(t) || _isObject(t));

    // MORETOP(void, T) = true.
    if (s is VoidType) return true;

    // MORETOP(S, void) = false.
    if (t is VoidType) return false;

    // MORETOP(dynamic, T) = true.
    if (s is DynamicType) return true;

    // MORETOP(S, dynamic) = false.
    if (t is DynamicType) return false;

    // MORETOP(Object, T) = true.
    if (s is InterfaceType &&
        s.classNode == objectClass &&
        s.nullability == Nullability.nonNullable) {
      return true;
    }

    // MORETOP(S, Object) = false.
    if (t is InterfaceType &&
        t.classNode == objectClass &&
        t.nullability == Nullability.nonNullable) {
      return false;
    }

    // MORETOP(S*, T*) = MORETOP(S, T).
    if (s.nullability == Nullability.legacy &&
        t.nullability == Nullability.legacy) {
      DartType nonNullableS = s.withNullability(Nullability.nonNullable);
      assert(s != nonNullableS);
      DartType nonNullableT = t.withNullability(Nullability.nonNullable);
      assert(t != nonNullableT);
      return moretop(nonNullableS, nonNullableT);
    }

    // MORETOP(S, T*) = true.
    if (s.nullability == Nullability.nonNullable &&
        t.nullability == Nullability.legacy) {
      return true;
    }

    // MORETOP(S*, T) = false.
    if (s.nullability == Nullability.legacy &&
        t.nullability == Nullability.nonNullable) {
      return false;
    }

    // MORETOP(S?, T?) == MORETOP(S, T).
    if (s.nullability == Nullability.nullable &&
        t.nullability == Nullability.nullable) {
      DartType nonNullableS = s.withNullability(Nullability.nonNullable);
      assert(s != nonNullableS);
      DartType nonNullableT = t.withNullability(Nullability.nonNullable);
      assert(t != nonNullableT);
      return moretop(nonNullableS, nonNullableT);
    }

    // MORETOP(S, T?) = true.
    if (s.nullability == Nullability.nonNullable &&
        t.nullability == Nullability.nullable) {
      return true;
    }

    // MORETOP(S?, T) = false.
    if (s.nullability == Nullability.nullable &&
        t.nullability == Nullability.nonNullable) {
      return false;
    }

    // TODO(dmitryas): Update the following after the spec is updated.
    if (s.nullability == Nullability.nullable &&
        t.nullability == Nullability.legacy) {
      return true;
    }
    if (s.nullability == Nullability.legacy &&
        t.nullability == Nullability.nullable) {
      return false;
    }

    // MORETOP(FutureOr<S>, FutureOr<T>) = MORETOP(S, T).
    if (s is InterfaceType &&
        s.classNode == futureOrClass &&
        s.nullability == Nullability.nonNullable &&
        t is InterfaceType &&
        t.classNode == futureOrClass &&
        t.nullability == Nullability.nonNullable) {
      return moretop(s.typeArguments.single, t.typeArguments.single);
    }

    return internalProblem(
        templateInternalProblemUnsupported.withArguments("moretop($s, $t)"),
        -1,
        null);
  }

  /// Checks the value of the MOREBOTTOM predicate for [s] and [t].
  ///
  /// For the definition of MOREBOTTOM see the following:
  /// https://github.com/dart-lang/language/blob/master/resources/type-system/upper-lower-bounds.md#helper-predicates
  bool morebottom(DartType s, DartType t) {
    assert(_isBottom(s) || _isNull(s));
    assert(_isBottom(t) || _isNull(t));

    // MOREBOTTOM(Never, T) = true.
    if (s is NeverType && s.nullability == Nullability.nonNullable) {
      return true;
    }

    // MOREBOTTOM(S, Never) = false.
    if (t is NeverType && t.nullability == Nullability.nonNullable) {
      return false;
    }

    // MOREBOTTOM(Null, T) = true.
    if (s == nullType) {
      return true;
    }

    // MOREBOTTOM(S, Null) = false.
    if (t == nullType) {
      return false;
    }

    // MOREBOTTOM(S?, T?) = MOREBOTTOM(S, T).
    if (t.nullability == Nullability.nullable &&
        s.nullability == Nullability.nullable) {
      DartType nonNullableS = s.withNullability(Nullability.nonNullable);
      assert(s != nonNullableS);
      DartType nonNullableT = t.withNullability(Nullability.nonNullable);
      assert(t != nonNullableT);
      return morebottom(nonNullableS, nonNullableT);
    }

    // MOREBOTTOM(S, T?) = true.
    if (s.nullability == Nullability.nonNullable &&
        t.nullability == Nullability.nullable) {
      return true;
    }

    // MOREBOTTOM(S?, T) = false.
    if (s.nullability == Nullability.nullable &&
        t.nullability == Nullability.nonNullable) {
      return false;
    }

    // MOREBOTTOM(S*, T*) = MOREBOTTOM(S, T).
    if (s.nullability == Nullability.legacy &&
        t.nullability == Nullability.legacy) {
      DartType nonNullableS = s.withNullability(Nullability.nonNullable);
      assert(s != nonNullableS);
      DartType nonNullableT = t.withNullability(Nullability.nonNullable);
      assert(t != nonNullableT);
      return morebottom(nonNullableS, nonNullableT);
    }

    // MOREBOTTOM(S, T*) = true.
    if (s.nullability == Nullability.nonNullable &&
        t.nullability == Nullability.legacy) {
      return true;
    }

    // MOREBOTTOM(S*, T) = false.
    if (s.nullability == Nullability.legacy &&
        t.nullability == Nullability.nonNullable) {
      return false;
    }

    // TODO(dmitryas): Update the following after the spec is updated.
    if (s.nullability == Nullability.nullable &&
        t.nullability == Nullability.legacy) {
      return true;
    }
    if (s.nullability == Nullability.legacy &&
        t.nullability == Nullability.nullable) {
      return false;
    }

    // MOREBOTTOM(X&S, Y&T) = MOREBOTTOM(S, T).
    if (s is TypeParameterType &&
        s.promotedBound != null &&
        t is TypeParameterType &&
        t.promotedBound != null) {
      return morebottom(s.promotedBound, t.promotedBound);
    }

    // MOREBOTTOM(X&S, T) = true.
    if (s is TypeParameterType && s.promotedBound != null) {
      return true;
    }

    // MOREBOTTOM(S, X&T) = false.
    if (t is TypeParameterType && t.promotedBound != null) {
      return false;
    }

    // MOREBOTTOM(X extends S, Y extends T) = MOREBOTTOM(S, T).
    if (s is TypeParameterType && t is TypeParameterType) {
      assert(s.promotedBound == null);
      assert(t.promotedBound == null);
      return morebottom(s.parameter.bound, t.parameter.bound);
    }

    return internalProblem(
        templateInternalProblemUnsupported.withArguments("morebottom($s, $t)"),
        -1,
        null);
  }

  /// Computes the standard lower bound of [type1] and [type2].
  ///
  /// Standard lower bound is a lower bound function that imposes an
  /// ordering on the top types `void`, `dynamic`, and `object`.  This function
  /// additionally handles the unknown type that appears during type inference.
  DartType getStandardLowerBound(
      DartType type1, DartType type2, Library clientLibrary) {
    if (clientLibrary.isNonNullableByDefault) {
      return getNullabilityAwareStandardLowerBound(type1, type2, clientLibrary);
    }
    return getNullabilityObliviousStandardLowerBound(
        type1, type2, clientLibrary);
  }

  DartType getNullabilityAwareStandardLowerBound(
      DartType type1, DartType type2, Library clientLibrary) {
    // DOWN(T, T) = T.
    if (identical(type1, type2)) return type1;

    // For any type T, SLB(?, T) = SLB(T, ?) = T.
    if (type1 is UnknownType) return type2;
    if (type2 is UnknownType) return type1;

    // DOWN(T1, T2) where TOP(T1) and TOP(T2) =
    //   T1 if MORETOP(T2, T1)
    //   T2 otherwise
    // DOWN(T1, T2) = T2 if TOP(T1)
    // DOWN(T1, T2) = T1 if TOP(T2)
    if (_isTop(type1)) {
      if (_isTop(type2)) return moretop(type2, type1) ? type1 : type2;
      return type2;
    } else if (_isTop(type2)) {
      return type1;
    }

    // DOWN(T1, T2) where BOTTOM(T1) and BOTTOM(T2) =
    //   T1 if MOREBOTTOM(T1, T2)
    //   T2 otherwise
    // DOWN(T1, T2) = T2 if BOTTOM(T2)
    // DOWN(T1, T2) = T1 if BOTTOM(T1)
    if (_isBottom(type1)) {
      if (_isBottom(type2)) return morebottom(type1, type2) ? type1 : type2;
      return type1;
    } else if (_isBottom(type2)) {
      return type2;
    }

    // DOWN(T1, T2) where NULL(T1) and NULL(T2) =
    //   T1 if MOREBOTTOM(T1, T2)
    //   T2 otherwise
    // DOWN(Null, T2) =
    //   Null if Null <: T2
    //   Never otherwise
    // DOWN(T1, Null) =
    //  Null if Null <: T1
    //  Never otherwise
    if (_isNull(type1)) {
      if (_isNull(type2)) return morebottom(type1, type2) ? type1 : type2;
      Nullability type2Nullability = computeNullability(type2, futureOrClass);
      if (type2Nullability == Nullability.legacy ||
          type2Nullability == Nullability.nullable) {
        return type1;
      }
      return const NeverType(Nullability.nonNullable);
    } else if (_isNull(type2)) {
      Nullability type1Nullability = computeNullability(type1, futureOrClass);
      if (type1Nullability == Nullability.legacy ||
          type1Nullability == Nullability.nullable) {
        return type2;
      }
      return const NeverType(Nullability.nonNullable);
    }

    // DOWN(T1, T2) where OBJECT(T1) and OBJECT(T2) =
    //   T1 if MORETOP(T2, T1)
    //   T2 otherwise
    // DOWN(T1, T2) where OBJECT(T1) =
    //   T2 if T2 is non-nullable
    //   NonNull(T2) if NonNull(T2) is non-nullable
    //   Never otherwise
    // DOWN(T1, T2) where OBJECT(T2) =
    //   T1 if T1 is non-nullable
    //   NonNull(T1) if NonNull(T1) is non-nullable
    //   Never otherwise
    if (_isObject(type1)) {
      if (_isObject(type2)) return moretop(type2, type1) ? type1 : type2;
      Nullability type2Nullability = computeNullability(type2, futureOrClass);
      if (type2Nullability == Nullability.nonNullable) {
        return type2;
      }
      type2 = type2.withNullability(Nullability.nonNullable);
      type2Nullability = computeNullability(type2, futureOrClass);
      if (type2Nullability == Nullability.nonNullable) {
        return type2;
      }
      return const NeverType(Nullability.nonNullable);
    } else if (_isObject(type2)) {
      Nullability type1Nullability = computeNullability(type1, futureOrClass);
      if (type1Nullability == Nullability.nonNullable) {
        return type1;
      }
      type1 = type1.withNullability(Nullability.nonNullable);
      type1Nullability = computeNullability(type1, futureOrClass);
      if (type1Nullability == Nullability.nonNullable) {
        return type1;
      }
      return const NeverType(Nullability.nonNullable);
    }

    // The effect of the following rules is accounted for in the code below via
    // the invocations of intersectNullabilities.
    // DOWN(T1*, T2*) = S* where S is DOWN(T1, T2)
    // DOWN(T1*, T2?) = S* where S is DOWN(T1, T2)
    // DOWN(T1?, T2*) = S* where S is DOWN(T1, T2)
    // DOWN(T1*, T2) = S where S is DOWN(T1, T2)
    // DOWN(T1, T2*) = S where S is DOWN(T1, T2)
    // DOWN(T1?, T2?) = S? where S is DOWN(T1, T2)
    // DOWN(T1?, T2) = S where S is DOWN(T1, T2)
    // DOWN(T1, T2?) = S where S is DOWN(T1, T2)

    if (type1 is FunctionType && type2 is FunctionType) {
      return _getNullabilityAwareFunctionStandardLowerBound(
          type1, type2, clientLibrary);
    }

    // DOWN(T1, T2) = T1 if T1 <: T2.
    // DOWN(T1, T2) = T2 if T2 <: T1.
    DartType nonNullableType1 = type1.withNullability(Nullability.nonNullable);
    DartType nonNullableType2 = type2.withNullability(Nullability.nonNullable);
    if (isSubtypeOf(nonNullableType1, nonNullableType2,
        SubtypeCheckMode.withNullabilities)) {
      return type1.withNullability(
          intersectNullabilities(type1.nullability, type2.nullability));
    }
    if (isSubtypeOf(nonNullableType2, nonNullableType1,
        SubtypeCheckMode.withNullabilities)) {
      return type2.withNullability(
          intersectNullabilities(type1.nullability, type2.nullability));
    }

    // DOWN(T1, T2) = Never otherwise.
    return new NeverType(
        intersectNullabilities(type1.nullability, type2.nullability));
  }

  DartType getNullabilityObliviousStandardLowerBound(
      DartType type1, DartType type2, Library clientLibrary) {
    // For all types T, SLB(T,T) = T.  Note that we don't test for equality
    // because we don't want to make the algorithm quadratic.  This is ok
    // because the check is not needed for correctness; it's just a speed
    // optimization.
    if (identical(type1, type2)) {
      return type1;
    }

    // For any type T, SLB(?, T) = SLB(T, ?) = T.
    if (type1 is UnknownType) {
      return type2;
    }
    if (type2 is UnknownType) {
      return type1;
    }

    // SLB(void, T) = SLB(T, void) = T.
    if (type1 is VoidType) {
      return type2;
    }
    if (type2 is VoidType) {
      return type1;
    }

    // SLB(dynamic, T) = SLB(T, dynamic) = T if T is not void.
    if (type1 is DynamicType) {
      return type2;
    }
    if (type2 is DynamicType) {
      return type1;
    }

    // SLB(Object, T) = SLB(T, Object) = T if T is not void or dynamic.
    if (type1 == objectLegacyRawType) {
      return type2;
    }
    if (type2 == objectLegacyRawType) {
      return type1;
    }

    // SLB(bottom, T) = SLB(T, bottom) = bottom.
    if (type1 is BottomType) return type1;
    if (type2 is BottomType) return type2;
    if (type1 == nullType) return type1;
    if (type2 == nullType) return type2;

    // Function types have structural lower bounds.
    if (type1 is FunctionType && type2 is FunctionType) {
      return _getNullabilityObliviousFunctionStandardLowerBound(
          type1, type2, clientLibrary);
    }

    // Otherwise, the lower bounds  of two types is one of them it if it is a
    // subtype of the other.
    if (isSubtypeOf(type1, type2, SubtypeCheckMode.ignoringNullabilities)) {
      return type1;
    }

    if (isSubtypeOf(type2, type1, SubtypeCheckMode.ignoringNullabilities)) {
      return type2;
    }

    // See https://github.com/dart-lang/sdk/issues/37439#issuecomment-519654959.
    if (type1 is InterfaceType && type1.classNode == futureOrClass) {
      if (type2 is InterfaceType) {
        if (type2.classNode == futureOrClass) {
          // GLB(FutureOr<A>, FutureOr<B>) == FutureOr<GLB(A, B)>
          DartType argument = getStandardLowerBound(
              type1.typeArguments[0], type2.typeArguments[0], clientLibrary);
          return new InterfaceType(
              futureOrClass, argument.nullability, <DartType>[argument]);
        }
        if (type2.classNode == futureClass) {
          // GLB(FutureOr<A>, Future<B>) == Future<GLB(A, B)>
          return new InterfaceType(
              futureClass,
              intersectNullabilities(
                  computeNullabilityOfFutureOr(type1, futureOrClass),
                  type2.nullability),
              <DartType>[
                getStandardLowerBound(type1.typeArguments[0],
                    type2.typeArguments[0], clientLibrary)
              ]);
        }
      }
      // GLB(FutureOr<A>, B) == GLB(A, B)
      return getStandardLowerBound(
          type1.typeArguments[0], type2, clientLibrary);
    }
    // The if-statement below handles the following rule:
    //     GLB(A, FutureOr<B>) ==  GLB(FutureOr<B>, A)
    // It's broken down into sub-cases instead of making a recursive call to
    // avoid making the checks that were already made above.  Note that at this
    // point it's not possible for type1 to be a FutureOr.
    if (type2 is InterfaceType && type2.classNode == futureOrClass) {
      if (type1 is InterfaceType && type1.classNode == futureClass) {
        // GLB(Future<A>, FutureOr<B>) == Future<GLB(B, A)>
        return new InterfaceType(
            futureClass,
            intersectNullabilities(type1.nullability,
                computeNullabilityOfFutureOr(type2, futureOrClass)),
            <DartType>[
              getStandardLowerBound(
                  type2.typeArguments[0], type1.typeArguments[0], clientLibrary)
            ]);
      }
      // GLB(A, FutureOr<B>) == GLB(B, A)
      return getStandardLowerBound(
          type2.typeArguments[0], type1, clientLibrary);
    }

    // No subtype relation, so the lower bound is bottom.
    return const BottomType();
  }

  /// Computes the standard upper bound of two types.
  ///
  /// Standard upper bound is an upper bound function that imposes an ordering
  /// on the top types 'void', 'dynamic', and `object`.  This function
  /// additionally handles the unknown type that appears during type inference.
  DartType getStandardUpperBound(
      DartType type1, DartType type2, Library clientLibrary) {
    if (clientLibrary.isNonNullableByDefault) {
      return getNullabilityAwareStandardUpperBound(type1, type2, clientLibrary);
    }
    return getNullabilityObliviousStandardUpperBound(
        type1, type2, clientLibrary);
  }

  DartType getNullabilityAwareStandardUpperBound(
      DartType type1, DartType type2, Library clientLibrary) {
    // UP(T, T) = T
    if (identical(type1, type2)) return type1;

    // For any type T, SUB(?, T) = SUB(T, ?) = T.
    if (type1 is UnknownType) return type2;
    if (type2 is UnknownType) return type1;

    // UP(T1, T2) where TOP(T1) and TOP(T2) =
    //   T1 if MORETOP(T1, T2)
    //   T2 otherwise
    // UP(T1, T2) = T1 if TOP(T1)
    // UP(T1, T2) = T2 if TOP(T2)
    if (_isTop(type1)) {
      if (_isTop(type2)) return moretop(type1, type2) ? type1 : type2;
      return type1;
    } else if (_isTop(type2)) {
      return type2;
    }

    // UP(T1, T2) where BOTTOM(T1) and BOTTOM(T2) =
    //   T2 if MOREBOTTOM(T1, T2)
    //   T1 otherwise
    // UP(T1, T2) = T2 if BOTTOM(T1)
    // UP(T1, T2) = T1 if BOTTOM(T2)
    if (_isBottom(type1)) {
      if (_isBottom(type2)) return morebottom(type1, type2) ? type2 : type1;
      return type2;
    } else if (_isBottom(type2)) {
      return type1;
    }

    // UP(T1, T2) where NULL(T1) and NULL(T2) =
    //   T2 if MOREBOTTOM(T1, T2)
    //   T1 otherwise
    // UP(T1, T2) where NULL(T1) =
    //   T2 if T2 is nullable
    //   T2? otherwise
    // UP(T1, T2) where NULL(T2) =
    //   T1 if T1 is nullable
    //   T1? otherwise
    if (_isNull(type1)) {
      if (_isNull(type2)) return morebottom(type1, type2) ? type2 : type1;
      return type2.withNullability(Nullability.nullable);
    } else if (_isNull(type2)) {
      return type1.withNullability(Nullability.nullable);
    }

    // UP(T1, T2) where OBJECT(T1) and OBJECT(T2) =
    //   T1 if MORETOP(T1, T2)
    //   T2 otherwise
    // UP(T1, T2) where OBJECT(T1) =
    //   T1 if T2 is non-nullable
    //   T1? otherwise
    // UP(T1, T2) where OBJECT(T2) =
    //   T2 if T1 is non-nullable
    //   T2? otherwise
    if (_isObject(type1)) {
      if (_isObject(type2)) return moretop(type1, type2) ? type1 : type2;
      if (computeNullability(type2, futureOrClass) == Nullability.nonNullable) {
        return type1;
      }
      return type1.withNullability(Nullability.nullable);
    } else if (_isObject(type2)) {
      if (computeNullability(type1, futureOrClass) == Nullability.nonNullable) {
        return type2;
      }
      return type2.withNullability(Nullability.nullable);
    }

    // The effect of the following rules is accounted for in the code below via
    // the invocations of uniteNullabilities.
    // UP(T1*, T2*) = S* where S is UP(T1, T2)
    // UP(T1*, T2?) = S? where S is UP(T1, T2)
    // UP(T1?, T2*) = S? where S is UP(T1, T2)
    // UP(T1*, T2) = S* where S is UP(T1, T2)
    // UP(T1, T2*) = S* where S is UP(T1, T2)
    // UP(T1?, T2?) = S? where S is UP(T1, T2)
    // UP(T1?, T2) = S? where S is UP(T1, T2)
    // UP(T1, T2?) = S? where S is UP(T1, T2)

    if (type1 is TypeParameterType) {
      return _getNullabilityAwareTypeParameterStandardUpperBound(
          type1, type2, clientLibrary);
    }

    if (type2 is TypeParameterType) {
      return _getNullabilityAwareTypeParameterStandardUpperBound(
          type2, type1, clientLibrary);
    }

    if (type1 is FunctionType) {
      if (type2 is FunctionType) {
        return _getNullabilityAwareFunctionStandardUpperBound(
            type1, type2, clientLibrary);
      }

      if (type2 is InterfaceType && type2.classNode == functionClass) {
        // UP(T Function<...>(...), Function) = Function
        return functionRawType(
            uniteNullabilities(type1.nullability, type2.nullability));
      }

      // UP(T Function<...>(...), T2) = Object
      return objectRawType(
          uniteNullabilities(type1.nullability, type2.nullability));
    } else if (type2 is FunctionType) {
      if (type1 is InterfaceType && type1.classNode == functionClass) {
        // UP(Function, T Function<...>(...)) = Function
        return functionRawType(
            uniteNullabilities(type1.nullability, type2.nullability));
      }

      // UP(T1, T Function<...>(...)) = Object
      return objectRawType(
          uniteNullabilities(type1.nullability, type2.nullability));
    }

    // UP(T1, T2) = T2 if T1 <: T2
    //   Note that both types must be class types at this point.
    assert(type1 is InterfaceType,
        "Expected type1 to be an interface type, got '${type1.runtimeType}'.");
    assert(type2 is InterfaceType,
        "Expected type2 to be an interface type, got '${type2.runtimeType}'.");
    if (isSubtypeOf(type1, type2, SubtypeCheckMode.withNullabilities)) {
      return type2.withNullability(
          uniteNullabilities(type1.nullability, type2.nullability));
    }

    // UP(T1, T2) = T1 if T2 <: T1
    //   Note that both types must be class types at this point.
    if (isSubtypeOf(type2, type1, SubtypeCheckMode.withNullabilities)) {
      return type1.withNullability(
          uniteNullabilities(type1.nullability, type2.nullability));
    }

    // UP(C<T0, ..., Tn>, C<S0, ..., Sn>) = C<R0,..., Rn> where Ri is UP(Ti, Si)
    if (type1 is InterfaceType && type2 is InterfaceType) {
      Class klass = type1.classNode;
      if (type2.classNode == klass) {
        int n = klass.typeParameters.length;
        List<DartType> leftArguments = type1.typeArguments;
        List<DartType> rightArguments = type2.typeArguments;
        List<DartType> typeArguments = new List<DartType>(n);
        for (int i = 0; i < n; ++i) {
          int variance = klass.typeParameters[i].variance;
          if (variance == Variance.contravariant) {
            typeArguments[i] = getNullabilityAwareStandardLowerBound(
                leftArguments[i], rightArguments[i], clientLibrary);
          } else if (variance == Variance.invariant) {
            if (!areMutualSubtypes(leftArguments[i], rightArguments[i],
                SubtypeCheckMode.withNullabilities)) {
              return getLegacyLeastUpperBound(type1, type2, clientLibrary);
            }
          } else {
            typeArguments[i] = getNullabilityAwareStandardUpperBound(
                leftArguments[i], rightArguments[i], clientLibrary);
          }
        }
        return new InterfaceType(
            klass,
            uniteNullabilities(type1.nullability, type2.nullability),
            typeArguments);
      }
    }

    // UP(C0<T0, ..., Tn>, C1<S0, ..., Sk>)
    //   = least upper bound of two interfaces as in Dart 1.
    return getLegacyLeastUpperBound(type1, type2, clientLibrary);
  }

  /// Computes the nullability-aware lower bound of two function types.
  ///
  /// The algorithm is defined as follows:
  /// DOWN(
  ///   <X0 extends B00, ..., Xm extends B0m>(P00, ..., P0k) -> T0,
  ///   <X0 extends B10, ..., Xm extends B1m>(P10, ..., P1l) -> T1)
  /// =
  ///   <X0 extends B20, ..., Xm extends B2m>(P20, ..., P2q) -> R0
  /// if:
  ///   each B0i and B1i are equal types (syntactically),
  ///   q is max(k, l),
  ///   R0 is DOWN(T0, T1),
  ///   B2i is B0i,
  ///   P2i is UP(P0i, P1i) for i <= than min(k, l),
  ///   P2i is P0i for k < i <= q,
  ///   P2i is P1i for l < i <= q, and
  ///   P2i is optional if P0i or P1i is optional.
  ///
  /// DOWN(
  ///   <X0 extends B00, ..., Xm extends B0m>(P00, ..., P0k, Named0) -> T0,
  ///   <X0 extends B10, ..., Xm extends B1m>(P10, ..., P1k, Named1) -> T1)
  /// =
  ///   <X0 extends B20, ..., Xm extends B2m>(P20, ..., P2k, Named2) -> R0
  /// if:
  ///   each B0i and B1i are equal types (syntactically),
  ///   R0 is DOWN(T0, T1),
  ///   B2i is B0i,
  ///   P2i is UP(P0i, P1i),
  ///   Named2 contains R2i xi for each xi in both Named0 and Named1,
  ///     where R0i xi is in Named0,
  ///     where R1i xi is in Named1,
  ///     and R2i is UP(R0i, R1i),
  ///     and R2i xi is required if xi is required in both Named0 and Named1,
  ///   Named2 contains R0i xi for each xi in Named0 and not Named1,
  ///     where xi is optional in Named2,
  ///   Named2 contains R1i xi for each xi in Named1 and not Named0, and
  ///     where xi is optional in Named2.
  /// DOWN(T Function<...>(...), S Function<...>(...)) = Never otherwise.
  DartType _getNullabilityAwareFunctionStandardLowerBound(
      FunctionType f, FunctionType g, Library clientLibrary) {
    bool haveNamed =
        f.namedParameters.isNotEmpty || g.namedParameters.isNotEmpty;
    bool haveOptionalPositional =
        f.requiredParameterCount < f.positionalParameters.length ||
            g.requiredParameterCount < g.positionalParameters.length;

    // The fallback result for whenever the following rule applies:
    //     DOWN(T Function<...>(...), S Function<...>(...)) = Never otherwise.
    final DartType fallbackResult =
        new NeverType(intersectNullabilities(f.nullability, g.nullability));

    if (haveNamed && haveOptionalPositional) return fallbackResult;
    if (haveNamed &&
        f.positionalParameters.length != g.positionalParameters.length) {
      return fallbackResult;
    }

    int m = f.typeParameters.length;
    bool boundsMatch = false;
    Substitution substitution = Substitution.empty;
    if (g.typeParameters.length == m) {
      boundsMatch = true;
      if (m != 0) {
        Map<TypeParameter, DartType> substitutionMap =
            <TypeParameter, DartType>{};
        for (int i = 0; i < m; ++i) {
          substitutionMap[g.typeParameters[i]] =
              new TypeParameterType.forAlphaRenaming(
                  g.typeParameters[i], f.typeParameters[i]);
        }
        substitution = Substitution.fromMap(substitutionMap);
        for (int i = 0; i < m && boundsMatch; ++i) {
          // TODO(dmitryas): Figure out if a procedure for syntactic equality
          // should be used instead.
          if (!areMutualSubtypes(
              f.typeParameters[i].bound,
              substitution.substituteType(g.typeParameters[i].bound),
              SubtypeCheckMode.withNullabilities)) {
            boundsMatch = false;
          }
        }
      }
    }
    if (!boundsMatch) return fallbackResult;
    int maxPos =
        math.max(f.positionalParameters.length, g.positionalParameters.length);
    int minPos =
        math.min(f.positionalParameters.length, g.positionalParameters.length);

    List<TypeParameter> typeParameters = f.typeParameters;

    List<DartType> positionalParameters =
        new List<DartType>.filled(maxPos, null);
    for (int i = 0; i < minPos; ++i) {
      positionalParameters[i] = getNullabilityAwareStandardUpperBound(
          f.positionalParameters[i],
          substitution.substituteType(g.positionalParameters[i]),
          clientLibrary);
    }
    for (int i = minPos; i < f.positionalParameters.length; ++i) {
      positionalParameters[i] = f.positionalParameters[i];
    }
    for (int i = minPos; i < g.positionalParameters.length; ++i) {
      positionalParameters[i] =
          substitution.substituteType(g.positionalParameters[i]);
    }

    List<NamedType> namedParameters = <NamedType>[];
    {
      // Assuming that the named parameters of both types are sorted
      // lexicographically.
      int i = 0;
      int j = 0;
      while (i < f.namedParameters.length && j < g.namedParameters.length) {
        NamedType named1 = f.namedParameters[i];
        NamedType named2 = g.namedParameters[j];
        int order = named1.name.compareTo(named2.name);
        NamedType named;
        if (order < 0) {
          named = new NamedType(named1.name, named1.type, isRequired: false);
          ++i;
        } else if (order > 0) {
          named = !named2.isRequired
              ? named2
              : new NamedType(
                  named2.name, substitution.substituteType(named2.type),
                  isRequired: false);
          ++j;
        } else {
          named = new NamedType(
              named1.name,
              getNullabilityAwareStandardUpperBound(named1.type,
                  substitution.substituteType(named2.type), clientLibrary),
              isRequired: named1.isRequired && named2.isRequired);
          ++i;
          ++j;
        }
        namedParameters.add(named);
      }
      while (i < f.namedParameters.length) {
        NamedType named1 = f.namedParameters[i];
        namedParameters.add(!named1.isRequired
            ? named1
            : new NamedType(named1.name, named1.type, isRequired: false));
        ++i;
      }
      while (j < g.namedParameters.length) {
        NamedType named2 = g.namedParameters[j];
        namedParameters.add(new NamedType(
            named2.name, substitution.substituteType(named2.type),
            isRequired: false));
        ++j;
      }
    }

    DartType returnType = getNullabilityAwareStandardLowerBound(
        f.returnType, substitution.substituteType(g.returnType), clientLibrary);

    return new FunctionType(positionalParameters, returnType,
        intersectNullabilities(f.nullability, g.nullability),
        namedParameters: namedParameters,
        typeParameters: typeParameters,
        requiredParameterCount: minPos);
  }

  /// Computes the nullability-aware lower bound of two function types.
  ///
  /// UP(
  ///   <X0 extends B00, ... Xm extends B0m>(P00, ... P0k) -> T0,
  ///   <X0 extends B10, ... Xm extends B1m>(P10, ... P1l) -> T1)
  /// =
  ///   <X0 extends B20, ..., Xm extends B2m>(P20, ..., P2q) -> R0
  /// if:
  ///   each B0i and B1i are equal types (syntactically)
  ///   Both have the same number of required positional parameters
  ///   q is min(k, l)
  ///   R0 is UP(T0, T1)
  ///   B2i is B0i
  ///   P2i is DOWN(P0i, P1i)
  /// UP(
  ///   <X0 extends B00, ... Xm extends B0m>(P00, ... P0k, Named0) -> T0,
  ///   <X0 extends B10, ... Xm extends B1m>(P10, ... P1k, Named1) -> T1)
  /// =
  ///   <X0 extends B20, ..., Xm extends B2m>(P20, ..., P2k, Named2) -> R0
  /// if:
  ///   each B0i and B1i are equal types (syntactically)
  ///   All positional parameters are required
  ///   R0 is UP(T0, T1)
  ///   B2i is B0i
  ///   P2i is DOWN(P0i, P1i)
  ///   Named0 contains R0i xi
  ///       if R1i xi is a required named parameter in Named1
  ///   Named1 contains R1i xi
  ///       if R0i xi is a required named parameter in Named0
  ///   Named2 contains exactly R2i xi
  ///       for each xi in both Named0 and Named1
  ///     where R0i xi is in Named0
  ///     where R1i xi is in Named1
  ///     and R2i is DOWN(R0i, R1i)
  ///     and R2i xi is required
  ///         if xi is required in either Named0 or Named1
  /// UP(T Function<...>(...), S Function<...>(...)) = Function otherwise
  DartType _getNullabilityAwareFunctionStandardUpperBound(
      FunctionType f, FunctionType g, Library clientLibrary) {
    bool haveNamed =
        f.namedParameters.isNotEmpty || g.namedParameters.isNotEmpty;
    bool haveOptionalPositional =
        f.requiredParameterCount < f.positionalParameters.length ||
            g.requiredParameterCount < g.positionalParameters.length;

    // The return value for whenever the following applies:
    //     UP(T Function<...>(...), S Function<...>(...)) = Function otherwise
    final DartType fallbackResult =
        functionRawType(uniteNullabilities(f.nullability, g.nullability));

    if (haveNamed && haveOptionalPositional) return fallbackResult;
    if (!haveNamed && f.requiredParameterCount != g.requiredParameterCount) {
      return fallbackResult;
    }
    // Here we perform a quick check on the function types to figure out if we
    // can compute a non-trivial upper bound for them.  The check isn't merged
    // with the computation of the non-trivial upper bound itself to avoid
    // performing unnecessary computations.
    if (haveNamed) {
      if (f.positionalParameters.length != g.positionalParameters.length) {
        return fallbackResult;
      }
      // Assuming that the named parameters are sorted lexicographically in
      // both type1 and type2.
      int i = 0;
      int j = 0;
      while (i < f.namedParameters.length && j < g.namedParameters.length) {
        NamedType named1 = f.namedParameters[i];
        NamedType named2 = g.namedParameters[j];
        int order = named1.name.compareTo(named2.name);
        if (order < 0) {
          if (named1.isRequired) return fallbackResult;
          ++i;
        } else if (order > 0) {
          if (named2.isRequired) return fallbackResult;
          ++j;
        } else {
          ++i;
          ++j;
        }
      }
      while (i < f.namedParameters.length) {
        if (f.namedParameters[i].isRequired) return fallbackResult;
        ++i;
      }
      while (j < g.namedParameters.length) {
        if (g.namedParameters[j].isRequired) return fallbackResult;
        ++j;
      }
    }

    int m = f.typeParameters.length;
    bool boundsMatch = false;
    Substitution substitution = Substitution.empty;
    if (g.typeParameters.length == m) {
      boundsMatch = true;
      if (m != 0) {
        Map<TypeParameter, DartType> substitutionMap =
            <TypeParameter, DartType>{};
        for (int i = 0; i < m; ++i) {
          substitutionMap[g.typeParameters[i]] =
              new TypeParameterType.forAlphaRenaming(
                  g.typeParameters[i], f.typeParameters[i]);
        }
        substitution = Substitution.fromMap(substitutionMap);
        for (int i = 0; i < m && boundsMatch; ++i) {
          // TODO(dmitryas): Figure out if a procedure for syntactic
          // equality should be used instead.
          if (!areMutualSubtypes(
              f.typeParameters[i].bound,
              substitution.substituteType(g.typeParameters[i].bound),
              SubtypeCheckMode.withNullabilities)) {
            boundsMatch = false;
          }
        }
      }
    }
    if (!boundsMatch) return fallbackResult;
    int minPos =
        math.min(f.positionalParameters.length, g.positionalParameters.length);

    List<TypeParameter> typeParameters = f.typeParameters;

    List<DartType> positionalParameters =
        new List<DartType>.filled(minPos, null);
    for (int i = 0; i < minPos; ++i) {
      positionalParameters[i] = getNullabilityAwareStandardLowerBound(
          f.positionalParameters[i],
          substitution.substituteType(g.positionalParameters[i]),
          clientLibrary);
    }

    List<NamedType> namedParameters = <NamedType>[];
    {
      // Assuming that the named parameters of both types are sorted
      // lexicographically.
      int i = 0;
      int j = 0;
      while (i < f.namedParameters.length && j < g.namedParameters.length) {
        NamedType named1 = f.namedParameters[i];
        NamedType named2 = g.namedParameters[j];
        int order = named1.name.compareTo(named2.name);
        if (order < 0) {
          ++i;
        } else if (order > 0) {
          ++j;
        } else {
          namedParameters.add(new NamedType(
              named1.name,
              getNullabilityAwareStandardLowerBound(named1.type,
                  substitution.substituteType(named2.type), clientLibrary),
              isRequired: named1.isRequired || named2.isRequired));
          ++i;
          ++j;
        }
      }
    }

    DartType returnType = getNullabilityAwareStandardUpperBound(
        f.returnType, substitution.substituteType(g.returnType), clientLibrary);

    return new FunctionType(positionalParameters, returnType,
        uniteNullabilities(f.nullability, g.nullability),
        namedParameters: namedParameters,
        typeParameters: typeParameters,
        requiredParameterCount: f.requiredParameterCount);
  }

  DartType _getNullabilityAwareTypeParameterStandardUpperBound(
      TypeParameterType type1, DartType type2, Library clientLibrary) {
    if (type1.promotedBound == null) {
      // UP(X1 extends B1, T2) =
      //   T2 if X1 <: T2
      //   otherwise X1 if T2 <: X1
      //   otherwise UP(B1[Object/X1], T2)
      if (isSubtypeOf(type1, type2, SubtypeCheckMode.withNullabilities)) {
        return type2.withNullability(
            uniteNullabilities(type1.nullability, type2.nullability));
      }
      if (isSubtypeOf(type2, type1, SubtypeCheckMode.withNullabilities)) {
        return type1.withNullability(
            uniteNullabilities(type1.nullability, type2.nullability));
      }
      Map<TypeParameter, DartType> substitution = <TypeParameter, DartType>{
        type1.parameter: objectNonNullableRawType
      };
      return getNullabilityAwareStandardUpperBound(
              substitute(type1.parameter.bound, substitution),
              type2,
              clientLibrary)
          .withNullability(
              uniteNullabilities(type1.nullability, type2.nullability));
    } else {
      // UP(X1 & B1, T2) =
      //   T2 if X1 <: T2
      //   otherwise X1 if T2 <: X1
      //   otherwise UP(B1[Object/X1], T2)
      DartType demoted = new TypeParameterType(
          type1.parameter, type1.typeParameterTypeNullability);
      if (isSubtypeOf(demoted, type2, SubtypeCheckMode.withNullabilities)) {
        return type2.withNullability(
            uniteNullabilities(type1.nullability, type2.nullability));
      }
      if (isSubtypeOf(type2, demoted, SubtypeCheckMode.withNullabilities)) {
        return demoted.withNullability(
            uniteNullabilities(type1.nullability, type2.nullability));
      }
      Map<TypeParameter, DartType> substitution = <TypeParameter, DartType>{
        type1.parameter: objectNonNullableRawType
      };
      return getNullabilityAwareStandardUpperBound(
              substitute(type1.promotedBound, substitution),
              type2,
              clientLibrary)
          .withNullability(
              uniteNullabilities(type1.nullability, type2.nullability));
    }
  }

  DartType getNullabilityObliviousStandardUpperBound(
      DartType type1, DartType type2, Library clientLibrary) {
    // For all types T, SUB(T,T) = T.  Note that we don't test for equality
    // because we don't want to make the algorithm quadratic.  This is ok
    // because the check is not needed for correctness; it's just a speed
    // optimization.
    if (identical(type1, type2)) {
      return type1;
    }

    // For any type T, SUB(?, T) = SUB(T, ?) = T.
    if (type1 is UnknownType) {
      return type2;
    }
    if (type2 is UnknownType) {
      return type1;
    }

    // SUB(void, T) = SUB(T, void) = void.
    if (type1 is VoidType) {
      return type1;
    }
    if (type2 is VoidType) {
      return type2;
    }

    // SUB(dynamic, T) = SUB(T, dynamic) = dynamic if T is not void.
    if (type1 is DynamicType) {
      return type1;
    }
    if (type2 is DynamicType) {
      return type2;
    }

    // SUB(Object, T) = SUB(T, Object) = Object if T is not void or dynamic.
    if (type1 == objectLegacyRawType) {
      return type1;
    }
    if (type2 == objectLegacyRawType) {
      return type2;
    }

    // SUB(bottom, T) = SUB(T, bottom) = T.
    if (type1 is BottomType) return type2;
    if (type2 is BottomType) return type1;
    if (type1 == nullType) return type2;
    if (type2 == nullType) return type1;

    if (type1 is TypeParameterType || type2 is TypeParameterType) {
      return _getNullabilityObliviousTypeParameterStandardUpperBound(
          type1, type2, clientLibrary);
    }

    // The standard upper bound of a function type and an interface type T is
    // the standard upper bound of Function and T.
    if (type1 is FunctionType && type2 is InterfaceType) {
      type1 = functionLegacyRawType;
    }
    if (type2 is FunctionType && type1 is InterfaceType) {
      type2 = functionLegacyRawType;
    }

    // At this point type1 and type2 should both either be interface types or
    // function types.
    if (type1 is InterfaceType && type2 is InterfaceType) {
      return _getInterfaceStandardUpperBound(type1, type2, clientLibrary);
    }

    if (type1 is FunctionType && type2 is FunctionType) {
      return _getNullabilityObliviousFunctionStandardUpperBound(
          type1, type2, clientLibrary);
    }

    if (type1 is InvalidType || type2 is InvalidType) {
      return const InvalidType();
    }

    // Should never happen. As a defensive measure, return the dynamic type.
    assert(false, "type1 = $type1; type2 = $type2");
    return const DynamicType();
  }

  /// Compute the standard lower bound of function types [f] and [g].
  ///
  /// The spec rules for SLB on function types, informally, are pretty simple:
  ///
  /// - If a parameter is required in both, it stays required.
  ///
  /// - If a positional parameter is optional or missing in one, it becomes
  ///   optional.  (This is because we're trying to build a function type which
  ///   is a subtype of both [f] and [g], meaning it accepts all possible inputs
  ///   that [f] and [g] accept.)
  ///
  /// - Named parameters are unioned together.
  ///
  /// - For any parameter that exists in both functions, use the SUB of them as
  ///   the resulting parameter type.
  ///
  /// - Use the SLB of their return types.
  DartType _getNullabilityObliviousFunctionStandardLowerBound(
      FunctionType f, FunctionType g, Library clientLibrary) {
    // TODO(rnystrom,paulberry): Right now, this assumes f and g do not have any
    // type parameters. Revisit that in the presence of generic methods.

    // Calculate the SUB of each corresponding pair of parameters.
    int totalPositional =
        math.max(f.positionalParameters.length, g.positionalParameters.length);
    List<DartType> positionalParameters = new List<DartType>(totalPositional);
    for (int i = 0; i < totalPositional; i++) {
      if (i < f.positionalParameters.length) {
        DartType fType = f.positionalParameters[i];
        if (i < g.positionalParameters.length) {
          DartType gType = g.positionalParameters[i];
          positionalParameters[i] =
              getStandardUpperBound(fType, gType, clientLibrary);
        } else {
          positionalParameters[i] = fType;
        }
      } else {
        positionalParameters[i] = g.positionalParameters[i];
      }
    }

    // Parameters that are required in both functions are required in the
    // result.  Parameters that are optional or missing in either end up
    // optional.
    int requiredParameterCount =
        math.min(f.requiredParameterCount, g.requiredParameterCount);
    bool hasPositional = requiredParameterCount < totalPositional;

    // Union the named parameters together.
    List<NamedType> namedParameters = [];
    {
      int i = 0;
      int j = 0;
      while (true) {
        if (i < f.namedParameters.length) {
          if (j < g.namedParameters.length) {
            String fName = f.namedParameters[i].name;
            String gName = g.namedParameters[j].name;
            int order = fName.compareTo(gName);
            if (order < 0) {
              namedParameters.add(f.namedParameters[i++]);
            } else if (order > 0) {
              namedParameters.add(g.namedParameters[j++]);
            } else {
              namedParameters.add(new NamedType(
                  fName,
                  getStandardUpperBound(f.namedParameters[i++].type,
                      g.namedParameters[j++].type, clientLibrary)));
            }
          } else {
            namedParameters.addAll(f.namedParameters.skip(i));
            break;
          }
        } else {
          namedParameters.addAll(g.namedParameters.skip(j));
          break;
        }
      }
    }
    bool hasNamed = namedParameters.isNotEmpty;

    // Edge case. Dart does not support functions with both optional positional
    // and named parameters. If we would synthesize that, give up.
    if (hasPositional && hasNamed) return const BottomType();

    // Calculate the SLB of the return type.
    DartType returnType =
        getStandardLowerBound(f.returnType, g.returnType, clientLibrary);
    return new FunctionType(positionalParameters, returnType,
        intersectNullabilities(f.nullability, g.nullability),
        namedParameters: namedParameters,
        requiredParameterCount: requiredParameterCount);
  }

  /// Compute the standard upper bound of function types [f] and [g].
  ///
  /// The rules for SUB on function types, informally, are pretty simple:
  ///
  /// - If the functions don't have the same number of required parameters,
  ///   always return `Function`.
  ///
  /// - Discard any optional named or positional parameters the two types do not
  ///   have in common.
  ///
  /// - Compute the SLB of each corresponding pair of parameter types, and the
  ///   SUB of the return types.  Return a function type with those types.
  DartType _getNullabilityObliviousFunctionStandardUpperBound(
      FunctionType f, FunctionType g, Library clientLibrary) {
    // TODO(rnystrom): Right now, this assumes f and g do not have any type
    // parameters. Revisit that in the presence of generic methods.

    // If F and G differ in their number of required parameters, then the
    // standard upper bound of F and G is Function.
    // TODO(paulberry): We could do better here, e.g.:
    //   SUB(([int]) -> void, (int) -> void) = (int) -> void
    if (f.requiredParameterCount != g.requiredParameterCount) {
      return new InterfaceType(
          functionClass,
          uniteNullabilities(f.nullability, g.nullability),
          const <DynamicType>[]);
    }
    int requiredParameterCount = f.requiredParameterCount;

    // Calculate the SLB of each corresponding pair of parameters.
    // Ignore any extra optional positional parameters if one has more than the
    // other.
    int totalPositional =
        math.min(f.positionalParameters.length, g.positionalParameters.length);
    List<DartType> positionalParameters = new List<DartType>(totalPositional);
    for (int i = 0; i < totalPositional; i++) {
      positionalParameters[i] = getStandardLowerBound(
          f.positionalParameters[i], g.positionalParameters[i], clientLibrary);
    }

    // Intersect the named parameters.
    List<NamedType> namedParameters = [];
    {
      int i = 0;
      int j = 0;
      while (true) {
        if (i < f.namedParameters.length) {
          if (j < g.namedParameters.length) {
            String fName = f.namedParameters[i].name;
            String gName = g.namedParameters[j].name;
            int order = fName.compareTo(gName);
            if (order < 0) {
              i++;
            } else if (order > 0) {
              j++;
            } else {
              namedParameters.add(new NamedType(
                  fName,
                  getStandardLowerBound(f.namedParameters[i++].type,
                      g.namedParameters[j++].type, clientLibrary)));
            }
          } else {
            break;
          }
        } else {
          break;
        }
      }
    }

    // Calculate the SUB of the return type.
    DartType returnType =
        getStandardUpperBound(f.returnType, g.returnType, clientLibrary);
    return new FunctionType(positionalParameters, returnType,
        uniteNullabilities(f.nullability, g.nullability),
        namedParameters: namedParameters,
        requiredParameterCount: requiredParameterCount);
  }

  DartType _getInterfaceStandardUpperBound(
      InterfaceType type1, InterfaceType type2, Library clientLibrary) {
    // This currently does not implement a very complete standard upper bound
    // algorithm, but handles a couple of the very common cases that are
    // causing pain in real code.  The current algorithm is:
    // 1. If either of the types is a supertype of the other, return it.
    //    This is in fact the best result in this case.
    // 2. If the two types have the same class element and is implicitly or
    //    explicitly covariant, then take the pointwise standard upper bound of
    //    the type arguments. This is again the best result, except that the
    //    recursive calls may not return the true standard upper bounds.  The
    //    result is guaranteed to be a well-formed type under the assumption
    //    that the input types were well-formed (and assuming that the
    //    recursive calls return well-formed types).
    //    If the variance of the type parameter is contravariant, we take the
    //    standard lower bound of the type arguments. If the variance of the
    //    type parameter is invariant, we verify if the type arguments satisfy
    //    subtyping in both directions, then choose a bound.
    // 3. Otherwise return the spec-defined standard upper bound.  This will
    //    be an upper bound, might (or might not) be least, and might
    //    (or might not) be a well-formed type.
    if (isSubtypeOf(type1, type2, SubtypeCheckMode.ignoringNullabilities)) {
      return type2;
    }
    if (isSubtypeOf(type2, type1, SubtypeCheckMode.ignoringNullabilities)) {
      return type1;
    }
    if (type1 is InterfaceType &&
        type2 is InterfaceType &&
        identical(type1.classNode, type2.classNode)) {
      List<DartType> tArgs1 = type1.typeArguments;
      List<DartType> tArgs2 = type2.typeArguments;
      List<TypeParameter> tParams = type1.classNode.typeParameters;

      assert(tArgs1.length == tArgs2.length);
      assert(tArgs1.length == tParams.length);
      List<DartType> tArgs = new List(tArgs1.length);
      for (int i = 0; i < tArgs1.length; i++) {
        if (tParams[i].variance == Variance.contravariant) {
          tArgs[i] = getStandardLowerBound(tArgs1[i], tArgs2[i], clientLibrary);
        } else if (tParams[i].variance == Variance.invariant) {
          if (!areMutualSubtypes(
              tArgs1[i], tArgs2[i], SubtypeCheckMode.ignoringNullabilities)) {
            // No bound will be valid, find bound at the interface level.
            return getLegacyLeastUpperBound(type1, type2, clientLibrary);
          }
          // TODO (kallentu) : Fix asymmetric bounds behavior for invariant type
          //  parameters.
          tArgs[i] = tArgs1[i];
        } else {
          tArgs[i] = getStandardUpperBound(tArgs1[i], tArgs2[i], clientLibrary);
        }
      }
      return new InterfaceType(type1.classNode,
          uniteNullabilities(type1.nullability, type2.nullability), tArgs);
    }
    return getLegacyLeastUpperBound(type1, type2, clientLibrary);
  }

  DartType _getNullabilityObliviousTypeParameterStandardUpperBound(
      DartType type1, DartType type2, Library clientLibrary) {
    // This currently just implements a simple standard upper bound to
    // handle some common cases.  It also avoids some termination issues
    // with the naive spec algorithm.  The standard upper bound of two types
    // (at least one of which is a type parameter) is computed here as:
    // 1. If either type is a supertype of the other, return it.
    // 2. If the first type is a type parameter, replace it with its bound,
    //    with recursive occurrences of itself replaced with Object.
    //    The second part of this should ensure termination.  Informally,
    //    each type variable instantiation in one of the arguments to the
    //    standard upper bound algorithm now strictly reduces the number
    //    of bound variables in scope in that argument position.
    // 3. If the second type is a type parameter, do the symmetric operation
    //    to #2.
    //
    // It's not immediately obvious why this is symmetric in the case that both
    // of them are type parameters.  For #1, symmetry holds since subtype
    // is antisymmetric.  For #2, it's clearly not symmetric if upper bounds of
    // bottom are allowed.  Ignoring this (for various reasons, not least
    // of which that there's no way to write it), there's an informal
    // argument (that might even be right) that you will always either
    // end up expanding both of them or else returning the same result no matter
    // which order you expand them in.  A key observation is that
    // identical(expand(type1), type2) => subtype(type1, type2)
    // and hence the contra-positive.
    //
    // TODO(leafp): Think this through and figure out what's the right
    // definition.  Be careful about termination.
    //
    // I suspect in general a reasonable algorithm is to expand the innermost
    // type variable first.  Alternatively, you could probably choose to treat
    // it as just an instance of the interface type upper bound problem, with
    // the "inheritance" chain extended by the bounds placed on the variables.
    if (isSubtypeOf(type1, type2, SubtypeCheckMode.ignoringNullabilities)) {
      return type2;
    }
    if (isSubtypeOf(type2, type1, SubtypeCheckMode.ignoringNullabilities)) {
      return type1;
    }
    if (type1 is TypeParameterType) {
      // TODO(paulberry): Analyzer collapses simple bounds in one step, i.e. for
      // C<T extends U, U extends List>, T gets resolved directly to List.  Do
      // we need to replicate that behavior?
      return getStandardUpperBound(
          Substitution.fromMap({type1.parameter: objectLegacyRawType})
              .substituteType(type1.parameter.bound),
          type2,
          clientLibrary);
    } else if (type2 is TypeParameterType) {
      return getStandardUpperBound(
          type1,
          Substitution.fromMap({type2.parameter: objectLegacyRawType})
              .substituteType(type2.parameter.bound),
          clientLibrary);
    } else {
      // We should only be called when at least one of the types is a
      // TypeParameterType
      assert(false);
      return const DynamicType();
    }
  }
}
