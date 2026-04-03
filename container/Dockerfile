FROM node:20

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Dev tools
RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  zsh \
  fzf \
  neovim \
  jq \
  procps \
  sudo \
  less \
  man-db \
  unzip \
  zip \
  curl \
  bat \
  ripgrep \
  btop \
  gnupg2 \
  gh \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && ln -s /usr/bin/batcat /usr/local/bin/bat

# Docker CE CLI
RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
  && chmod a+r /etc/apt/keyrings/docker.asc \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
     https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
     > /etc/apt/sources.list.d/docker.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# git-delta
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) \
  && wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
  && dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
  && rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Passwordless sudo for node user
RUN echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node \
  && chmod 0440 /etc/sudoers.d/node

# Locale
RUN apt-get update && apt-get install -y --no-install-recommends locales \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# BATS (testing) and ShellCheck (linting)
RUN apt-get update && apt-get install -y --no-install-recommends shellcheck \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats \
  && /tmp/bats/install.sh /usr/local \
  && rm -rf /tmp/bats

# Directories and permissions
RUN mkdir -p /workspace /home/node/.claude /home/node/.codex /commandhistory /usr/local/share/npm-global \
  && chown -R node:node /workspace /home/node/.claude /home/node/.codex /commandhistory /usr/local/share/npm-global

# Shell history persistence
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && touch /commandhistory/.bash_history \
  && chown -R node /commandhistory

ENV DEVCONTAINER=true
ENV SHELL=/bin/zsh

WORKDIR /workspace

# Switch to non-root user
USER node

# Global npm packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# zsh with powerlevel10k
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Claude Code
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Codex CLI
RUN npm install -g @openai/codex

# SDKMAN (no JDK — projects provide their own via .sdkmanrc)
RUN curl -s "https://get.sdkman.io" | bash
