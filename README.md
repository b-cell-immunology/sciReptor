sciReptor - single-cell immunoglobulin repertoire analysis toolkit
------------------------------------------------------------------

###Installation

Due to several external tools and various dependencies, sciReptor will take
around half an hour to be setup up. A [step-by-step guide](INSTALLATION.md)
for the host and the toolkit itself (including demo datasets) is available.
However, in case you want to have a look at it first, there is also a
completely set up **[virtual machine available][]** (as VirtualBox 5.0
appliance), which contains everything including three pre-installed demo
datasets.

[virtual machine available]: http://b-cell-immunology.dkfz.de/sciReptor_VMs/

###Related repositories

- [sciReptor_library](https://github.com/b-cell-immunology/sciReptor_library)
  is a set positional data files and processing scripts, which download the 
  the reference sequences and build the internal and BLAST databases used by
  sciReptor.
- [sciReptor_analysis](https://github.com/b-cell-immunology/sciReptor_analysis)
  contains various scripts for downstream repertoire analysis.

###Citing sciReptor

If you are using sciReptor or its subcomponents in a publication please cite:

Imkeller K, Arndt PF, Wardemann H, Busse CE. sciReptor: analysis of single-cell
level immunoglobulin repertoires. BMC Bioinformatics 17:67 (2016)
PMID: [26847109](https://www.ncbi.nlm.nih.gov/pubmed/26847109)
DOI: [10.1186/s12859-016-0920-1](https://dx.doi.org/10.1186/s12859-016-0920-1)

###Copyright and License

Copyright (2011-2016) Katharina Imkeller, Christian Busse, Irina Czogiel and
Peter Arndt.

sciReptor is free software: you can redistribute it and/or modify it under
the terms of the [GNU Affero General Public License][] as published by the
Free Software Foundation, either version 3 of the License, or (at your
option) any later version.

sciReptor is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
for more details.

You should have received a copy of the GNU Affero General Public License
along with sciReptor. If not, see <http://www.gnu.org/licenses/>.

[GNU Affero General Public License]:https://www.gnu.org/licenses/agpl.html
