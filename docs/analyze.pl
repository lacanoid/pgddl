#!/usr/bin/perl

open(Fi,"<","../ddlx.sql") || die;

print <<"END";
digraph pg_ddl {
rankdir = LR
END

my $f;
while(my $l=<Fi>) {
    if($l=~/^create [\w\s]*?function (ddlx_[a-zA-Z0-9_]+)\(/i) {
        $f = $1;        
        print "# $f\n";
        next;
    }
    if($l=~/(ddlx_[a-zA-Z0-9_]+)\(/i) {
        my $f2 = $1;
        print qq{"$f" -> "$f2";\n};
    }
}

print <<"END";
}
END


close(Fi);
