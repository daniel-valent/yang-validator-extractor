FROM python:3.10-bullseye
ARG YANG_ID
ARG YANG_GID
ARG YANGCATALOG_CONFIG_PATH
ARG CONFD_VERSION
ARG YANGLINT_VERSION
ARG XYM_VERSION
ARG VALIDATOR_JDK_VERSION
ARG MAVEN_VERSION
ARG LYV_VERSION

ENV YANG_ID "$YANG_ID"
ENV YANG_GID "$YANG_GID"
ENV YANGCATALOG_CONFIG_PATH "$YANGCATALOG_CONFIG_PATH"
ENV CONFD_VERSION "$CONFD_VERSION"
ENV YANGLINT_VERSION "$YANGLINT_VERSION"
ENV XYM_VERSION "$XYM_VERSION"
ENV VALIDATOR_JDK_VERSION "$VALIDATOR_JDK_VERSION"
ENV MAVEN_VERSION "$MAVEN_VERSION"
ENV LYV_VERSION "$LYV_VERSION"
ENV VIRTUAL_ENV=/home/yangvalidator/yang-extractor-validator

RUN apt-get -y update
RUN apt-get install -y clang cmake git gnupg2 gunicorn openssh-client rsyslog unzip wget

# Create 'yang' user and group
RUN groupadd -g ${YANG_GID} -r yang && useradd --no-log-init -r -g yang -u ${YANG_ID} -d /home yang

WORKDIR /home
RUN git clone -b ${YANGLINT_VERSION} --single-branch --depth 1 https://github.com/CESNET/libyang.git
RUN mkdir -p /home/libyang/build
WORKDIR /home/libyang/build
RUN cmake -D CMAKE_BUILD_TYPE:String="Release" .. && make && make install

WORKDIR /home
# Set up java and maven
RUN wget https://download.oracle.com/java/${VALIDATOR_JDK_VERSION}/latest/jdk-${VALIDATOR_JDK_VERSION}_linux-x64_bin.deb
RUN dpkg -i jdk-${VALIDATOR_JDK_VERSION}_linux-x64_bin.deb

RUN wget https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.zip
RUN unzip apache-maven-${MAVEN_VERSION}-bin.zip -d /usr/local/bin/
RUN mv /usr/local/bin/apache-maven-${MAVEN_VERSION} /usr/local/bin/maven

# Set up Maven settings for building lighty-yang-validator
RUN mkdir -p /root/.m2
RUN wget -O /root/.m2/settings.xml https://raw.githubusercontent.com/opendaylight/odlparent/master/settings.xml

# Set up lighty-yang-validator
RUN mkdir -p /home/lyv/src
WORKDIR /home/lyv/src
RUN git clone -b ${LYV_VERSION} --depth 1 https://github.com/PANTHEONtech/lighty-yang-validator.git
WORKDIR /home/lyv/src/lighty-yang-validator
RUN /usr/local/bin/maven/bin/mvn clean install
RUN unzip ./target/lighty-yang-validator-*-bin.zip -d /home/lyv/
RUN mv /home/lyv/lighty-yang-validator-*/* /home/lyv/
RUN chmod +x /home/lyv/lyv

RUN sed -i "/imklog/s/^/#/" /etc/rsyslog.conf
RUN rm -rf /var/lib/apt/lists/*

WORKDIR /home
RUN pip3 install --upgrade pip
COPY ./yang-validator-extractor/requirements.txt .
RUN pip3 install -r requirements.txt
RUN pip3 install xym==${XYM_VERSION} -U
# TODO: remove next step from build when depend.py will be fixed in next pyang release
# https://github.com/mbj4668/pyang/pull/793
COPY ./yang-validator-extractor/pyang_plugin/depend.py /usr/lib/python3.6/site-packages/pyang/plugins/.

RUN mkdir -p /home/yangvalidator/confd-${CONFD_VERSION}
COPY ./resources/confd-${CONFD_VERSION}.linux.x86_64.installer.bin $VIRTUAL_ENV/confd-${CONFD_VERSION}.linux.x86_64.installer.bin
COPY ./resources/yumapro-client-21.10-12.deb11.amd64.deb $VIRTUAL_ENV/yumapro-client-21.10-12.deb11.amd64.deb
RUN $VIRTUAL_ENV/confd-${CONFD_VERSION}.linux.x86_64.installer.bin /home/yangvalidator/confd-${CONFD_VERSION}

WORKDIR $VIRTUAL_ENV
RUN dpkg -i $VIRTUAL_ENV/yumapro-client-21.10-12.deb11.amd64.deb
COPY ./yang-validator-extractor/ $VIRTUAL_ENV/
RUN chown -R ${YANG_ID}:${YANG_GID} /home
RUN mkdir /var/run/yang

EXPOSE 8090
# Support arbitrary UIDs as per OpenShift guidelines

CMD chown -R ${YANG_ID}:${YANG_GID} /var/run/yang && service rsyslog start && gunicorn yangvalidator.wsgi:application -c gunicorn.conf.py
