# syntax=docker/dockerfile:1

FROM node:12-buster as wwwstage

ARG KASMWEB_RELEASE="54b9bac920267e902af3c9dfca4c0f64cff92f41"

RUN \
  echo "**** build clientside ****" && \
  export QT_QPA_PLATFORM=offscreen && \
  export QT_QPA_FONTDIR=/usr/share/fonts && \
  mkdir /src && \
  cd /src && \
  wget https://github.com/kasmtech/noVNC/tarball/${KASMWEB_RELEASE} -O - \
    | tar  --strip-components=1 -xz && \
  npm install && \
  npm run-script build

RUN \
  echo "**** organize output ****" && \
  mkdir /build-out && \
  cd /src && \
  rm -rf node_modules/ && \
  cp -R ./* /build-out/ && \
  cd /build-out && \
  rm *.md && \
  rm AUTHORS && \
  cp index.html vnc.html && \
  mkdir Downloads

FROM ghcr.io/linuxserver/baseimage-fedora:39 as buildstage

ARG KASMVNC_RELEASE="d49d07b88113d28eb183ca7c0ca59990fae1153c"

COPY --from=wwwstage /build-out /www

RUN \
  echo "**** install build deps ****" && \
  dnf install -y \
    autoconf \
    automake \
    bzip2 \
    cmake \
    gcc \
    gcc-c++ \
    git \
    libdrm-devel \
    libepoxy-devel \
    libjpeg-turbo-devel \
    libjpeg-turbo-static \
    libpciaccess-devel \
    libtool \
    libwebp-devel \
    libX11-devel \
    libXau-devel \
    libxcb-devel \
    libXcursor-devel \
    libxcvt-devel \
    libXdmcp-devel \
    libXext-devel \
    libXfont2-devel \
    libxkbfile-devel \
    libXrandr-devel \
    libxshmfence-devel \
    libXtst-devel \
    mesa-libEGL-devel \
    mesa-libgbm-devel \
    mesa-libGL-devel \
    meson \
    nettle-devel \
    openssl-devel \
    patch \
    pixman-devel \
    wayland-devel \
    wget \
    xcb-util-devel \
    xcb-util-image-devel \
    xcb-util-keysyms-devel \
    xcb-util-renderutil-devel \
    xcb-util-wm-devel \
    xinit \
    xkbcomp \
    xkbcomp-devel \
    xkeyboard-config \
    xorg-x11-font-utils \
    xorg-x11-proto-devel \
    xorg-x11-server-common \
    xorg-x11-server-devel \
    xorg-x11-xtrans-devel

RUN \
  echo "**** build libjpeg-turbo ****" && \
  mkdir /jpeg-turbo && \
  JPEG_TURBO_RELEASE=$(curl -sX GET "https://api.github.com/repos/libjpeg-turbo/libjpeg-turbo/releases/latest" \
  | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  curl -o \
  /tmp/jpeg-turbo.tar.gz -L \
    "https://github.com/libjpeg-turbo/libjpeg-turbo/archive/${JPEG_TURBO_RELEASE}.tar.gz" && \
  tar xf \
  /tmp/jpeg-turbo.tar.gz -C \
    /jpeg-turbo/ --strip-components=1 && \
  cd /jpeg-turbo && \
  MAKEFLAGS=-j`nproc` \
  CFLAGS="-fpic" \
  cmake -DCMAKE_INSTALL_PREFIX=/usr/local -G"Unix Makefiles" && \
  make && \
  make install

RUN \
  echo "**** build kasmvnc ****" && \
  git clone https://github.com/kasmtech/KasmVNC.git src && \
  cd /src && \
  git checkout -f ${KASMVNC_release} && \
  sed -i \
    -e '/find_package(FLTK/s@^@#@' \
    -e '/add_subdirectory(tests/s@^@#@' \
    CMakeLists.txt && \
  cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DBUILD_VIEWER:BOOL=OFF \
    -DENABLE_GNUTLS:BOOL=OFF \
    . && \
  make -j4 && \
  echo "**** build xorg ****" && \
  XORG_VER="1.20.14" && \
  XORG_PATCH=$(echo "$XORG_VER" | grep -Po '^\d.\d+' | sed 's#\.##') && \
  wget --no-check-certificate \
    -O /tmp/xorg-server-${XORG_VER}.tar.gz \
    "https://www.x.org/archive/individual/xserver/xorg-server-${XORG_VER}.tar.gz" && \
  tar --strip-components=1 \
    -C unix/xserver \
    -xf /tmp/xorg-server-${XORG_VER}.tar.gz && \
  cd unix/xserver && \
  patch -Np1 -i ../xserver${XORG_PATCH}.patch && \
  patch -s -p0 < ../CVE-2022-2320-v1.20.patch && \
  autoreconf -i && \
  ./configure --prefix=/opt/kasmweb \
    --with-xkb-path=/usr/share/X11/xkb \
    --with-xkb-output=/var/lib/xkb \
    --with-xkb-bin-directory=/usr/bin \
    --with-default-font-path="/usr/share/fonts/X11/misc,/usr/share/fonts/X11/cyrillic,/usr/share/fonts/X11/100dpi/:unscaled,/usr/share/fonts/X11/75dpi/:unscaled,/usr/share/fonts/X11/Type1,/usr/share/fonts/X11/100dpi,/usr/share/fonts/X11/75dpi,built-ins" \
    --with-sha1=libcrypto \
    --without-dtrace \
    --disable-dri \
    --disable-static \
    --disable-xinerama \
    --disable-xvfb \
    --disable-xnest \
    --disable-xorg \
    --disable-dmx \
    --disable-xwin \
    --disable-xephyr \
    --disable-kdrive \
    --disable-config-hal \
    --disable-config-udev \
    --disable-dri2 \
    --enable-glx \
    --disable-xwayland \
    --enable-dri3 && \
  find . -name "Makefile" -exec sed -i 's/-Werror=array-bounds//g' {} \; && \
  make -j4

RUN \
  echo "**** generate final output ****" && \
  cd /src && \
  mkdir -p xorg.build/bin && \
  cd xorg.build/bin/ && \
  ln -s /src/unix/xserver/hw/vnc/Xvnc Xvnc && \
  cd .. && \
  mkdir -p man/man1 && \
  touch man/man1/Xserver.1 && \
  cp /src/unix/xserver/hw/vnc/Xvnc.man man/man1/Xvnc.1 && \
  mkdir lib && \
  cd lib && \
  ln -s /usr/lib64/dri dri && \
  cd /src && \
  mkdir -p builder/www && \
  cp -ax /www/* builder/www/ && \
  cp builder/www/index.html builder/www/vnc.html && \
  make servertarball && \
  mkdir /build-out && \
  tar xzf \
    kasmvnc-Linux*.tar.gz \
    -C /build-out/

# nodejs builder
FROM ghcr.io/linuxserver/baseimage-fedora:39 as nodebuilder
ARG KCLIENT_RELEASE

RUN \
  echo "**** install build deps ****" && \
  dnf install -y \
    curl \
    cmake \
    gcc \
    gcc-c++ \
    make \
    nodejs \
    pulseaudio-libs-devel \
    python3 

RUN \
  echo "**** grab source ****" && \
  mkdir -p /kclient && \
  if [ -z ${KCLIENT_RELEASE+x} ]; then \
    KCLIENT_RELEASE=$(curl -sX GET "https://api.github.com/repos/linuxserver/kclient/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  curl -o \
  /tmp/kclient.tar.gz -L \
    "https://github.com/linuxserver/kclient/archive/${KCLIENT_RELEASE}.tar.gz" && \
  tar xf \
  /tmp/kclient.tar.gz -C \
    /kclient/ --strip-components=1

RUN \
  echo "**** install node modules ****" && \
  cd /kclient && \
  npm install && \
  rm -f package-lock.json

# runtime stage
FROM ghcr.io/linuxserver/baseimage-fedora:39

# set version label
ARG BUILD_DATE
ARG VERSION
ARG KASMBINS_RELEASE="1.15.0"
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"
LABEL "com.kasmweb.image"="true"

# env
ENV DISPLAY=:1 \
    PERL5LIB=/usr/local/bin \
    OMP_WAIT_POLICY=PASSIVE \
    GOMP_SPINCOUNT=0 \
    HOME=/config \
    START_DOCKER=true \
    PULSE_RUNTIME_PATH=/defaults \
    NVIDIA_DRIVER_CAPABILITIES=all

# copy over build output
COPY --from=nodebuilder /kclient /kclient
COPY --from=buildstage /build-out/ /

RUN \
  echo "**** enable locales ****" && \
  rm -f /etc/rpm/macros.image-language-conf && \
  echo "**** install deps ****" && \
  dnf install -y \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm && \
  dnf install -y \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
  dnf install -y 'dnf-command(config-manager)' && \
  dnf config-manager \
    --add-repo \
    https://download.docker.com/linux/fedora/docker-ce.repo && \
  dnf install -y --setopt=install_weak_deps=False --best \
    ca-certificates \
    containerd.io \
    cups \
    cups-client \
    cups-pdf \
    dbus-x11 \
    docker-buildx-plugin \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin \
    ffmpeg \
    fuse-overlayfs \
    glibc-all-langpacks \
    glibc-locale-source \
    google-noto-emoji-fonts \
    google-noto-sans-fonts \
    intel-media-driver \
    libjpeg-turbo \
    libstdc++ \
    libwebp \
    libXfont2 \
    libxshmfence \
    mesa-dri-drivers \
    mesa-libgbm \
    mesa-libGL \
    mesa-va-drivers \
    nginx \
    nodejs \
    openbox \
    openssh-clients \
    openssl \
    pciutils-libs \
    perl \
    perl-DateTime \
    perl-Hash-Merge-Simple \
    perl-List-MoreUtils \
    perl-Switch \
    perl-Try-Tiny \
    perl-YAML-Tiny \
    pixman \
    pulseaudio \
    pulseaudio-utils \
    python3 \
    python3-pyxdg \
    setxkbmap \
    util-linux \
    xauth \
    xkbcomp \
    xkeyboard-config \
    xorg-x11-drv-amdgpu \
    xorg-x11-drv-ati \
    xorg-x11-drv-intel \
    xorg-x11-drv-nouveau \
    xorg-x11-drv-qxl \
    xterm && \
  echo "**** printer config ****" && \
  sed -i -r \
    -e "s:^(Out\s).*:\1/home/kasm-user/PDF:" \
    /etc/cups/cups-pdf.conf && \
  echo "**** filesystem setup ****" && \
  ln -s /usr/local/share/kasmvnc /usr/share/kasmvnc && \
  ln -s /usr/local/etc/kasmvnc /etc/kasmvnc && \
  ln -s /usr/local/lib/kasmvnc /usr/lib/kasmvncserver && \
  echo "**** openbox tweaks ****" && \
  sed -i \
    -e 's/NLIMC/NLMC/g' \
    -e 's|</applications>|  <application class="*"><maximized>yes</maximized></application>\n</applications>|' \
    -e 's|</keyboard>|  <keybind key="C-S-d"><action name="ToggleDecorations"/></keybind>\n</keyboard>|' \
    /etc/xdg/openbox/rc.xml && \
  echo "**** user perms ****" && \
  echo "abc:abc" | chpasswd && \
  usermod -s /bin/bash abc && \
  echo '%wheel ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/wheel && \
  usermod -G wheel abc && \
  echo "**** kasm support ****" && \
  useradd \
    -u 1000 -U \
    -d /home/kasm-user \
    -s /bin/bash kasm-user && \
  echo "kasm-user:kasm" | chpasswd && \
  usermod -G wheel kasm-user && \
  mkdir -p /home/kasm-user && \
  chown 1000:1000 /home/kasm-user && \
  mkdir -p /var/run/pulse && \
  chown 1000:root /var/run/pulse && \
  mkdir -p /kasmbins && \
  curl -s https://kasm-ci.s3.amazonaws.com/kasmbins-amd64-${KASMBINS_RELEASE}.tar.gz \
    | tar xzvf - -C /kasmbins/ && \
  chmod +x /kasmbins/* && \
  chown -R 1000:1000 /kasmbins && \
  chown 1000:1000 /usr/share/kasmvnc/www/Downloads && \
  echo "**** dind support ****" && \
  groupadd -r dockremap && \
  useradd -r -g dockremap dockremap && \
  echo 'dockremap:165536:65536' >> /etc/subuid && \
  echo 'dockremap:165536:65536' >> /etc/subgid && \
  curl -o \
  /usr/local/bin/dind -L \
    https://raw.githubusercontent.com/moby/moby/master/hack/dind && \
  chmod +x /usr/local/bin/dind && \
  usermod -aG docker abc && \
  echo "**** configure locale ****" && \
  for LOCALE in $(curl -sL https://raw.githubusercontent.com/thelamer/lang-stash/master/langs); do \
    localedef -i $LOCALE -f UTF-8 $LOCALE.UTF-8; \
  done && \
  echo "**** theme ****" && \
  curl -s https://raw.githubusercontent.com/thelamer/lang-stash/master/theme.tar.gz \
    | tar xzvf - -C /usr/share/themes/Clearlooks/openbox-3/ && \
  echo "**** cleanup ****" && \
  dnf autoremove -y && \
  dnf clean all && \
  rm -rf \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000 3001
VOLUME /config
