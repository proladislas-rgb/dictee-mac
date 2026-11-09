# Lance le module natif de Verbe (verbe-lecture.dylib) depuis /usr/bin/perl, binaire système dont l'identifiant
# (com.apple.perl…) est accepté par MediaRemote. Usage : /usr/bin/perl lanceur.pl chemin/verbe-lecture.dylib
use strict; use warnings; use DynaLoader;
my $lib = shift or die "usage: lanceur.pl module.dylib\n";
my $h = DynaLoader::dl_load_file($lib, 0) or die "chargement impossible : " . DynaLoader::dl_error() . "\n";
my $s = DynaLoader::dl_find_symbol($h, "verbe_lecture_main") or die "point d'entrée introuvable\n";
my $f = DynaLoader::dl_install_xsub("main::verbe_lecture_main", $s);
&$f();
