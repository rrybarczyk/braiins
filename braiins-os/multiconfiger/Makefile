
REQUESTS_MODULE_PATH := $(shell dirname `python3 -c 'print(__import__("requests").__file__)'`)
multiconfiger.zip: multiconfiger.py
	test -d $(REQUESTS_MODULE_PATH)
	$(eval TMPDIR := $(shell mktemp -d))
	$(eval ARCHIVEDIR := $(TMPDIR)/multiconfiger)
	mkdir $(ARCHIVEDIR)
	cp multiconfiger.py $(ARCHIVEDIR)/multiconfiger
	cp -r $(REQUESTS_MODULE_PATH) $(ARCHIVEDIR)/
	sed -i 's/DEVEL/$(shell git show -s --format=%h)/g' $(ARCHIVEDIR)/multiconfiger
	cd $(TMPDIR) &&  zip multiconfiger.zip multiconfiger/multiconfiger multiconfiger/requests/*.py
	cp $(TMPDIR)/multiconfiger.zip .
	rm -r $(TMPDIR)

clean:
	rm -f multiconfiger.zip error.log

.PHONY: clean
