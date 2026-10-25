# Hermes Agent + Bot Desktop (Xfce acessível via VNC/RFB)
#
# A imagem oficial já traz TODO o código do desktop (tools/bot_desktop/launcher.sh,
# computer_use, cua-driver e o relay RFB do dashboard em hermes_cli/web_routers/
# display.py). O que falta na tag `latest` são só os binários do display stack.
# `tools/bot_desktop/runtime.py` lista exatamente estes pacotes em PACKAGES["apt"]
# e os binários em REQUIRED_BINARIES — o build verifica os dois no final.
#
# Instalar em runtime (botão "Install" do painel Screen / `hermes screen install`)
# funciona, mas cai na camada efêmera do container e some ao recriar. Fazer no
# Dockerfile garante que qualquer `docker compose up` já suba com o desktop pronto.
#
# Alternativa sem build: a tag oficial `nousresearch/hermes-agent:latest-desktop`
# é um superset exato desta camada (mesmos pacotes + `chromium` do apt). Use este
# Dockerfile se precisar fixar versão, adicionar pacotes ou reduzir o tamanho.
#
# Fixe a base numa tag de release (ex.: v0.22.5) em produção:
#   docker build --build-arg HERMES_BASE=nousresearch/hermes-agent:v0.22.5 -t hermes-agent-desktop .
ARG HERMES_BASE=nousresearch/hermes-agent:latest
FROM ${HERMES_BASE}

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Display stack do Bot Desktop. Componentes do Xfce são iniciados um a um pelo
# launcher.sh (nunca xfce4-session, que exige sessão logind) — por isso só os
# pacotes de componente, sem o metapacote xfce4 (que arrasta screensaver/polkit).
# DEBIAN_FRONTEND só vale para este passo: não fica no ambiente em runtime.
RUN DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 update \
 && apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
        tigervnc-standalone-server \
        xfce4-panel \
        xfwm4 \
        xfdesktop4 \
        xfce4-settings \
        xfce4-terminal \
        dbus-x11 \
        x11-xserver-utils \
        x11-utils \
        x11-xkb-utils \
        xauth \
        fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/*

# Chromium via apt (fallback para hosts com user namespaces restritos) não é
# necessário: o Chromium headed já vem fixado em /opt/hermes/tools/chromium-*/
# (PLAYWRIGHT_BROWSERS_PATH) e é o que o launcher usa. Descomente se o pane
# reclamar de "Chrome not found" em ambiente restrito.
# RUN apt-get update && apt-get install -y --no-install-recommends chromium \
#  && rm -rf /var/lib/apt/lists/*

# Falha o build — e não a primeira abertura do painel Screen — se algum binário
# exigido pelo launcher não existir, e confirma o que o runtime reporta.
RUN set -eu; \
    missing=0; \
    for bin in Xvnc xfwm4 xfce4-panel xfdesktop xfsettingsd dbus-run-session xauth xdpyinfo setxkbmap xprop; do \
        if ! command -v "$bin" >/dev/null 2>&1; then echo "missing binary: $bin" >&2; missing=1; fi; \
    done; \
    [ "$missing" -eq 0 ] || exit 1; \
    "$HERMES_PYTHON" -c 'from tools.bot_desktop import runtime; m = runtime.missing_binaries(); print("bot-desktop missing:", m); raise SystemExit(1 if m else 0)'; \
    echo "bot-desktop display stack OK"

# Nada é iniciado no boot: Xvnc + Xfce sobem sob demanda (painel Screen, tool
# computer_use ou browser headed) como o usuário `hermes`, num socket Unix 0600.
# A detecção é feita pelos binários: tools/bot_desktop/runtime.py -> missing_binaries().
