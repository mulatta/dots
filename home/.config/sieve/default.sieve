require ["fileinto", "mailbox"];

# GitHub notifications
if anyof (
    address :domain :is "from" "github.com",
    address :domain :is "from" "noreply.github.com"
) {
    fileinto :create "GitHub";
    stop;
}

# Academic - journals, preprints, conferences
if anyof (
    # Major publishers
    address :domain :is "from" "nature.com",
    address :domain :is "from" "springer.com",
    address :domain :is "from" "springernature.com",
    address :domain :is "from" "cell.com",
    address :domain :is "from" "sciencemag.org",
    address :domain :is "from" "science.org",
    address :domain :is "from" "pnas.org",
    address :domain :is "from" "plos.org",
    address :domain :is "from" "oup.com",
    address :domain :is "from" "wiley.com",
    address :domain :is "from" "elsevier.com",
    address :domain :is "from" "sciencedirect.com",
    address :domain :is "from" "frontiersin.org",
    address :domain :is "from" "mdpi.com",
    address :domain :is "from" "bmj.com",
    address :domain :is "from" "lancet.com",
    address :domain :is "from" "nejm.org",
    address :domain :is "from" "jci.org",
    address :domain :is "from" "elifesciences.org",
    # Preprint servers
    address :domain :is "from" "biorxiv.org",
    address :domain :is "from" "medrxiv.org",
    address :domain :is "from" "arxiv.org",
    address :domain :is "from" "researchsquare.com",
    address :domain :is "from" "ssrn.com",
    # Academic services
    address :domain :is "from" "pubmed.gov",
    address :domain :is "from" "ncbi.nlm.nih.gov",
    address :domain :is "from" "nih.gov",
    address :domain :is "from" "researchgate.net",
    address :domain :is "from" "academia.edu",
    address :domain :is "from" "mendeley.com",
    address :domain :is "from" "zotero.org",
    address :domain :is "from" "orcid.org",
    # Conferences
    address :domain :is "from" "acm.org",
    address :domain :is "from" "ieee.org",
    address :domain :is "from" "easychair.org",
    address :domain :is "from" "openreview.net",
    address :domain :is "from" "hotcrp.com",
    # Bioinformatics
    address :domain :is "from" "bioconductor.org",
    address :domain :is "from" "ensembl.org",
    address :domain :is "from" "uniprot.org",
    address :domain :is "from" "ebi.ac.uk",
    address :domain :is "from" "illumina.com",
    address :domain :is "from" "10xgenomics.com",
    # Google Scholar alerts
    header :contains "from" "scholaralerts-noreply@google.com"
) {
    fileinto :create "Academic";
    stop;
}

# Server / Infrastructure alerts
if anyof (
    address :domain :is "from" "mulatta.io",
    address :domain :is "from" "vultr.com",
    address :domain :is "from" "hetzner.com",
    address :domain :is "from" "cloudflare.com",
    address :domain :is "from" "letsencrypt.org",
    header :contains "from" "root@",
    header :contains "from" "admin@",
    header :contains "subject" "[cron]",
    header :contains "subject" "Cron"
) {
    fileinto :create "Server";
    stop;
}

# Default: keep in inbox
# Client-side (afew + Claude) handles fine-grained tagging
keep;
