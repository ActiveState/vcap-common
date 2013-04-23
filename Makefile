#
# Makefile for stackato-vcap-vcap-common
#
# Used solely by packaging systems.
# Must support targets "all", "install", "uninstall".
#
# During the packaging install phase, the native packager will
# set either DESTDIR or prefix to the directory which serves as
# a root for collecting the package files.
#
# The resulting package installs in /home/stackato/stackato/vcap,
# is not intended to be relocatable.
#

NAME=stackato-vcap-vcap-common

INSTALLHOME=/home/stackato
INSTALLBASE=$(INSTALLHOME)/stackato
INSTALLROOT=$(INSTALLBASE)/vcap
DIRNAME=$(INSTALLROOT)/common

HOMEDIR=$(DESTDIR)$(prefix)$(INSTALLHOME)
BASEDIR=$(DESTDIR)$(prefix)$(INSTALLBASE)
INSTDIR=$(DESTDIR)$(prefix)$(DIRNAME)

RSYNC_EXCLUDE=--exclude=.git* --exclude=Makefile --exclude=.stackato-pkg --exclude=debian --exclude=etc

all:
	@ true

install:
	mkdir -p $(INSTDIR)
	rsync -ap . $(INSTDIR) $(RSYNC_EXCLUDE)
	if [ -d etc ] ; then rsync -ap etc $(BASEDIR) ; fi
	chown -Rh stackato.stackato $(HOMEDIR)

uninstall:
	rm -rf $(INSTDIR)

clean:
	@ true
