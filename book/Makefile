# Build the book (PDF) with pdflatex.  Run `make` from this directory.
MAIN := main
CHAPTERS := $(wildcard ch_*.tex)

$(MAIN).pdf: $(MAIN).tex $(CHAPTERS) Ada.pdf
	pdflatex -interaction=nonstopmode -halt-on-error $(MAIN).tex
	-makeindex $(MAIN).idx
	pdflatex -interaction=nonstopmode -halt-on-error $(MAIN).tex
	pdflatex -interaction=nonstopmode -halt-on-error $(MAIN).tex

# Vector cover logo: convert the committed Ada.svg to a PDF for \includegraphics.
# Ada.pdf is committed too, so a normal build never needs inkscape; this rule only
# re-runs if the SVG changes.
Ada.pdf: Ada.svg
	inkscape $< --export-type=pdf --export-filename=$@

.PHONY: clean
clean:
	rm -f $(MAIN).pdf *.aux *.log *.toc *.out *.idx *.ind *.ilg
