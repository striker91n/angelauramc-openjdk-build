#!/bin/bash
set -e

. setdevkitpath.sh

imagespath=openjdk-${TARGET_VERSION}/build/${JVM_PLATFORM}-${TARGET_JDK}-${JVM_VARIANTS}-${JDK_DEBUG_LEVEL}/images

rm -rf dizout jreout jdkout dSYM-temp
mkdir -p dizout dSYM-temp/{lib,bin}

if [[ "$BUILD_IOS" != "1" ]]; then
  cp freetype-$BUILD_FREETYPE_VERSION/build_android-$TARGET_SHORT/lib/libfreetype.so $imagespath/jdk/lib/
fi

cp -r $imagespath/jdk jdkout

# JDK no longer create separate JRE image, so we have to create one manually.
# For iOS JDK 25, the boot JDK's jlink cannot read the jmods,
# so bypass jlink and create the JRE by copying from the JDK image.
if [[ "$BUILD_IOS" == "1" ]] && [[ $TARGET_VERSION -eq 25 ]]; then
  mkdir -p jreout/bin
  cp jdkout/bin/java jreout/bin/
  cp -r jdkout/{conf,legal,lib,release} jreout/
  rm -rf jreout/lib/jmods jreout/jmods
  rm -f jreout/lib/src.zip

  # Inject GetPropertyAction shim for Caciocavallo (removed from JDK 25's java.base)
  if command -v javac >/dev/null 2>&1; then
    SHIM_SRC=shim/sun/security/action/GetPropertyAction.java
    if [ -f "$SHIM_SRC" ]; then
      mkdir -p jreout/lib/shim-classes
      BOOT_JDK_JAVA=${JAVA_HOME:-$(/usr/libexec/java_home -v 24 2>/dev/null || true)}/bin
      ${BOOT_JDK_JAVA}/javac --release 8 -d jreout/lib/shim-classes "$SHIM_SRC"
      cd jreout/lib/shim-classes
      jar cf ../sun-security-action.jar .
      cd ../../..
      rm -rf jreout/lib/shim-classes
    fi
  fi
else
  # Produce the jre equivalent from the jdk
  # (https://blog.adoptium.net/2021/10/jlink-to-produce-own-runtime/)
  export EXTRA_JLINK_OPTION=
  if [[ "$TARGET_JDK" == "aarch64" ]] || [[ "$TARGET_JDK" == "x86_64" ]]; then
    echo "Building for aarch64 or x86_64, introducing JVMCI module"
    export EXTRA_JLINK_OPTION=,jdk.internal.vm.ci
  fi

  if [[ "$BUILD_IOS" != "1" ]]; then
    export JLINK_STRIP_ARG="--strip-native-debug-symbols=exclude-debuginfo-files:objcopy=${OBJCOPY}"
  else
    export JLINK_STRIP_ARG="--strip-debug"
  fi

  jlink \
  --module-path=jdkout/jmods \
  --add-modules $(ls jdkout/jmods/*.jmod 2>/dev/null | sed 's|.*/||; s|\.jmod||' | paste -sd, -)$EXTRA_JLINK_OPTION \
  --output jreout \
  $JLINK_STRIP_ARG \
  --no-man-pages \
  --no-header-files \
  --release-info=jdkout/release \
  --compress=0

  if [[ "$BUILD_IOS" != "1" ]]; then
    cp freetype-$BUILD_FREETYPE_VERSION/build_android-$TARGET_SHORT/lib/libfreetype.so jreout/lib/
  fi
fi

# mv jreout/lib/${TARGET_JDK}/libfontmanager.diz jreout/lib/${TARGET_JDK}/libfontmanager.diz.keep
# find jreout -name "*.debuginfo" | xargs -- rm
# mv jreout/lib/${TARGET_JDK}/libfontmanager.diz.keep jreout/lib/${TARGET_JDK}/libfontmanager.diz

#find jdkout -name "*.debuginfo" | xargs -- rm
find jdkout -name "*.debuginfo" -exec mv {}   dizout/ \;

find jdkout -name "*.dSYM"  | xargs -- rm -rf

#TODO: fix .dSYM stuff

if [[ "$BUILD_IOS" == "1" ]]; then
  install_name_tool -id @rpath/libfreetype.dylib jdkout/lib/libfreetype.dylib
  install_name_tool -id @rpath/libfreetype.dylib jreout/lib/libfreetype.dylib
  install_name_tool -change build_android-arm64/lib/libfreetype.dylib @rpath/libfreetype.dylib jdkout/lib/libfontmanager.dylib
  install_name_tool -change build_android-arm64/lib/libfreetype.dylib @rpath/libfreetype.dylib jreout/lib/libfontmanager.dylib

  for dafile in $(find j*out -name "*.dylib" -not -path "*.dSYM/*"); do
    install_name_tool -add_rpath @loader_path -add_rpath @loader_path/jli -add_rpath @loader_path/server \
      -add_rpath @loader_path/.. -add_rpath @loader_path/../jli -add_rpath @loader_path/../server $dafile || true
    ldid -Sios-sign-entitlements.xml $dafile
  done
  ldid -Sios-sign-entitlements.xml jreout/bin/*
  ldid -Sios-sign-entitlements.xml jdkout/bin/*
fi
