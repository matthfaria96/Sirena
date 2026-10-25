#!/bin/sh
# Gera o Sirena.zip e o Sirena-<versão>.dmg para distribuir a outras pessoas.
#
# O build normal assina com o certificado "Sirena Local Dev", que só existe e
# só é confiável neste Mac. Em outro Mac essa assinatura é de um certificado
# desconhecido, e o app não abre nem depois de "Abrir Mesmo Assim". Para
# distribuir sem conta paga de desenvolvedor, este script assina ad hoc
# (CODE_SIGN_IDENTITY=-) e desliga o Hardened Runtime, que só é necessário para
# notarizar e passa a exigir que os frameworks embutidos tenham o mesmo Team ID.
# Depois, se existir ~/Documents/witchmymac-release/sign-app.sh, reassina com o
# certificado witchmymac (ver abaixo), ainda sem Hardened Runtime.
set -eu

cd "$(dirname "$0")/.."

OUT=build/release
DERIVED=build/DerivedData-release
rm -rf "$OUT" "$DERIVED"
mkdir -p "$OUT"

xcodebuild -scheme Sirena -configuration Release -derivedDataPath "$DERIVED" \
  -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=NO \
  build

APP="$DERIVED/Build/Products/Release/Sirena.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

# O Xcode já assinou cada parte ad hoc, com os entitlements certos (a extensão
# do Finder precisa do sandbox). Neste Mac, sign-app.sh reassina tudo com o
# certificado autoassinado "witchmymac Code Signing", mantendo entitlements e
# flags: o requisito designado passa a ser 'identifier ... and certificate root
# = H"ff83cea4…"', igual de uma versão para outra, e o macOS não esquece mais as
# permissões (Acessibilidade, Gravação de Tela…) a cada atualização. O Sparkle
# aceita a atualização pela assinatura EdDSA do DMG e confere que a assinatura de
# código do app novo é válida. Sem o script (outro Mac), fica a assinatura ad hoc.
SIGN_APP="$HOME/Documents/witchmymac-release/sign-app.sh"
if [ -f "$SIGN_APP" ]; then
  sh "$SIGN_APP" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

# ditto preserva os links simbólicos dos frameworks; o zip comum os quebra e o
# macOS passa a dizer que o app está danificado.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/Sirena.zip"

STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Sirena.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Sirena -srcfolder "$STAGE" -ov -format UDZO "$OUT/Sirena-$VERSION.dmg"
rm -rf "$STAGE"

echo
echo "Pronto em $OUT:"
shasum -a 256 "$OUT/Sirena.zip" "$OUT/Sirena-$VERSION.dmg"
