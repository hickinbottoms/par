TARGETS = par.pl parcheck.pl
TARGET_DIR = /usr/local/bin
TARGET_DIR2 = /var/www/localhost/htdocs/wp-content/audio-processing

all:

install:
		cp $(TARGETS) $(TARGET_DIR)
		cp $(TARGETS) $(TARGET_DIR2)
