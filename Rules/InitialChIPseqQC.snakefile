from snakemake.utils import R
from os.path import join
import re

configfile: "run.json"
    
workpath = config['project']['workpath']    
filetype = config['project']['filetype']
readtype = config['project']['readtype']

extensions = [ "sorted.normalized", "sorted.mapq_gt_3.normalized", "sorted.dedup.normalized", "sorted.mapq_gt_3.dedup.normalized"]
extensions2 = list(map(lambda x:re.sub(".normalized","",x),extensions))

trim_dir='trim'

#kraken
kraken_dir='kraken'
bam_dir='bam'
bw_dir='bigwig'
ngsplot_dir='bam'
deeptools_dir='deeptools'
preseq_dir='preseq'
# 1 is yes and 0 is no... to remove blacklisted reads after trimming....output file is still ends with trim.fastq.gz
remove_blacklist_reads=1

#print(samples)

if readtype == 'Single' :
    rule InitialChIPseqQC:
        params: 
            batch='--time=168:00:00'
        input: 
            # Multiqc Report
            "Reports/multiqc_report.html",
            # QC
            "rawQC",
            "QC",
#             "QC_not_blacklist_plus", # not needed as merging blacklist removal into trimming
            # FastqScreen
            expand("FQscreen/{name}.R1.trim_screen.txt",name=samples),
            expand("FQscreen/{name}.R1.trim_screen.png",name=samples),
            # Trim and remove blacklisted reads
            expand(join(trim_dir,'{name}.R1.trim.fastq.gz'), name=samples),
#             expand(join(trim_dir,'{name}.R1.trim.not_blacklist_plus.fastq.gz'), name=samples),
            # Kraken
            expand(join(kraken_dir,"{name}.trim.fastq.kraken_bacteria.taxa.txt"),name=samples),
            expand(join(kraken_dir,"{name}.trim.fastq.kraken_bacteria.krona.html"),name=samples),
            join(kraken_dir,"kraken_bacteria.taxa.summary.txt"),
            # Align using BWA and dedup with Picard
            expand(join(bam_dir,"{name}.{ext}.bam"),name=samples,ext=extensions2),
            # BWA --> BigWig
            expand(join(bw_dir,"{name}.{ext}.bw",),name=samples,ext=extensions), 
            # PhantomPeakQualTools
            expand(join(bam_dir,"{name}.{ext}.ppqt"),name=samples,ext=extensions2),
            expand(join(bam_dir,"{name}.{ext}.pdf"),name=samples,ext=extensions2),
            # ngs.plot
            expand(join(ngsplot_dir,"{name}.{ext}.tss.max.heatmap.pdf"),name=samples,ext=extensions2),
            expand(join(ngsplot_dir,"{name}.{ext}.tss.km.heatmap.pdf"),name=samples,ext=extensions2),
            expand(join(ngsplot_dir,"{name}.{ext}.tes.max.heatmap.pdf"),name=samples,ext=extensions2),
            expand(join(ngsplot_dir,"{name}.{ext}.tes.km.heatmap.pdf"),name=samples,ext=extensions2),
            expand(join(ngsplot_dir,"{name}.{ext}.genebody.max.heatmap.pdf"),name=samples,ext=extensions2),
            expand(join(ngsplot_dir,"{name}.{ext}.genebody.km.heatmap.pdf"),name=samples,ext=extensions2),
            # deeptools
            expand(join(deeptools_dir,"spearman_heatmap.{ext}.pdf"),ext=extensions),
            expand(join(deeptools_dir,"pearson_heatmap.{ext}.pdf"),ext=extensions),
            expand(join(deeptools_dir,"spearman_scatterplot.{ext}.pdf"),ext=extensions),
            expand(join(deeptools_dir,"pearson_scatterplot.{ext}.pdf"),ext=extensions),
            expand(join(deeptools_dir,"pca.{ext}.pdf"),ext=extensions),
            # preseq
            expand(join(preseq_dir,"{name}.ccurve"),name=samples),


            # expand("{name}.sorted.rmdup.bam.bai", name=samples),
            # expand("{name}.sorted.rmdup.bam", name=samples),
            # expand("{name}.shifts", name=samples),
            # expand("{name}.rmdup.shifts", name=samples),

                   

    rule fastq_screen:
        input: 
            join(trim_dir,"{name}.R1.trim.fastq.gz")
        output:
            "FQscreen/{name}.R1.trim_screen.txt",
            "FQscreen/{name}.R1.trim_screen.png",
        params: 
            rname='pl:fqscreen',
            bowtie2ver=config['bin'][pfamily]['BOWTIE2VER'],
            config=config['references'][pfamily]['FASTQ_SCREEN_CONFIG'], 
            fastq_screen=config['bin'][pfamily]['FASTQ_SCREEN'],
            perlver=config['bin'][pfamily]['PERLVER'],
            outdir = "FQscreen",
        threads: 24
        shell:
            """
module load {params.bowtie2ver} ;
module load {params.perlver}; 
{params.fastq_screen} --conf {params.config} \
    --outdir {params.outdir} --subset 1000000 \
    --aligner bowtie2 --force {input}
            """

    rule rawfastqc:
        input: 
            expand("{name}.R1.fastq.gz", name=samples) 
        output: 
            'rawQC'
        priority: 2
        params: 
            rname='pl:rawfastqc',
            batch='--cpus-per-task=32 --mem=100g --time=48:00:00',
            fastqcver=config['bin'][pfamily]['FASTQCVER']
        threads: 32
        shell: 
            """
mkdir -p {output};
module load {params.fastqcver}; 
fastqc {input} -t {threads} -o {output}
            """

    rule trim_step1:
    #trimgalore to remove blatant adapters
        input:
            infq="{name}.R1.fastq.gz",
        output:
            outfq=temp(join(trim_dir,"{name}.R1_trimmed.fq.gz")),
        params:
            rname='pl:trim1',
            cutadaptver=config['bin'][pfamily]['CUTADAPTVER'],
            trimgalorever=config['bin'][pfamily]['TRIMGALOREVER'],
        shell:
            """
module load {params.cutadaptver};
module load {params.trimgalorever};

trim_galore --trim-n --gzip --length 35 -o trim {input.infq}
            """

    rule trim_step2:
    #polyX removal with afterqc
        input:
            infq=join(trim_dir,"{name}.R1_trimmed.fq.gz"),
        output:
            outfq=temp(join(trim_dir,"good","{name}.R1_trimmed.good.fq")),
            outfq_bad=temp(join(trim_dir,"bad","{name}.R1_trimmed.bad.fq")),
        params:
            rname='pl:trim2',
            afterqcver=config['bin'][pfamily]['AFTERQCVER'],
            trimdir=trim_dir,
        shell:
            """
module load {params.afterqcver};

after.py \
-1 {input.infq} \
-g {params.trimdir}/good \
-b {params.trimdir}/bad \
-r {params.trimdir}/afterQC
            """

    rule trim_step3:
    #remove any other adapter primers and move files
        input:
            infq=join(trim_dir,"good","{name}.R1_trimmed.good.fq"),
        output:
            outfq=temp(join(trim_dir,"{name}.R1.trim.beforeBLremoval.fastq.gz")),
        params:
            rname='pl:trim3',
            adaptersfa=config['references'][pfamily]['FASTAWITHADAPTERSETC'],
            bbtoolsver=config['bin'][pfamily]['BBTOOLSVER'],
            minlen=config['bin'][pfamily]['MINLEN'],
        shell:
            """
module load {params.bbtoolsver};

bbtools BBDuk \
-ktrim=r \
minlength={params.minlen} \
ref={params.adaptersfa} \
-Xmx40g \
in={input.infq} \
out={output.outfq}
            """
            
    rule trim_step4:
    # remove blacklist reads
        params:
            rname="pl:removeBL",
            reflen=config['references'][pfamily]['REFLEN'],
            blacklistbwaindex=config['references'][pfamily]['BLACKLISTBWAINDEX'],
            picardver=config['bin'][pfamily]['PICARDVER'],
            bwaver=config['bin'][pfamily]['BWAVER'],
            samtoolsver=config['bin'][pfamily]['SAMTOOLSVER'],
            remove_blacklist_reads=remove_blacklist_reads,
        input:
            infq=join(trim_dir,"{name}.R1.trim.beforeBLremoval.fastq.gz"),
        output:
            outfq=join(trim_dir,"{name}.R1.trim.fastq.gz"),
            outbam=temp(join(trim_dir,"{name}.R1.trim.not_blacklist_plus.bam")),    
        threads: 32
        shell:
            """
if [ {params.remove_blacklist_reads} -eq 1 ]; then
    module load {params.picardver};
    module load {params.bwaver};
    module load {params.samtoolsver};

    bwa mem -t {threads} {params.blacklistbwaindex} {input.infq} | samtools view -@{threads} -f4 -b -o {output.outbam}

    java -Xmx10g \
    -jar $PICARDJARPATH/SamToFastq.jar \
    VALIDATION_STRINGENCY=SILENT \
    INPUT={output.outbam} \
    FASTQ={output.outfq}
else
    mv {input.infq} {output.outfq}
    touch {output.outbam}
fi
            """

    rule kraken_se:
        input:
            fq = join(trim_dir,"{name}.R1.trim.fastq.gz"),
        output:
            krakenout = temp(join(kraken_dir,"{name}.trim.fastq.kraken_bacteria.out")),
            krakentaxa = join(kraken_dir,"{name}.trim.fastq.kraken_bacteria.taxa.txt"),
            kronahtml = join(kraken_dir,"{name}.trim.fastq.kraken_bacteria.krona.html"),
        params: 
            rname='pl:kraken',
            # batch='--cpus-per-task=32 --mem=200g --time=48:00:00', # does not work ... just add required resources in cluster.json ... make a new block for this rule there
            bacdb=config['references'][pfamily]['KRAKENBACDB'],
            krakenver=config['bin'][pfamily]['KRAKENVER'],
            kronatoolsver=config['bin'][pfamily]['KRONATOOLSVER'],
        threads: 32
        shell:
            """
module load {params.krakenver};
module load {params.kronatoolsver};

kraken --db {params.bacdb} --fastq-input --gzip-compressed --threads {threads} --output {output.krakenout} --preload {input.fq}
kraken-translate --mpa-format --db {params.bacdb} {output.krakenout} |cut -f2|sort|uniq -c|sort -k1,1nr > {output.krakentaxa}
cut -f2,3 {output.krakenout} | ktImportTaxonomy - -o {output.kronahtml}
rm -rf {output.kronahtml}.files
            """

    rule process_kraken:
        input:
            fq = expand(join(trim_dir,"{name}.R1.trim.fastq.gz"),name=samples),
            krakentaxa = expand(join(kraken_dir,"{name}.trim.fastq.kraken_bacteria.taxa.txt"),name=samples),
        output:
            kraken_taxa_summary = join(kraken_dir,"kraken_bacteria.taxa.summary.txt"),
        params:
            rname = "pl:krakenProcess",
        run:
            cmd="echo -ne \"Sample\tPercent\tBacteria\n\" > "+output.kraken_taxa_summary
            for f,t in zip(input.fq,input.krakentaxa):
                cmd="sh Scripts/kraken_process_taxa.sh "+f+" "+t+" >> "+output.kraken_taxa_summary
                shell(cmd)

    rule fastqc:  
        params:
            rname='pl:fastqc',
            batch='--cpus-per-task=32 --mem=110g --time=48:00:00',
            fastqcver=config['bin'][pfamily]['FASTQCVER']
        input:
            expand(join(trim_dir,"{name}.R1.trim.fastq.gz"),name=samples),
        output: "QC"
        priority: 2
        threads: 32
        shell: 
            """
mkdir -p {output};
module load {params.fastqcver}; 
fastqc {input} -t {threads} -o {output}
            """

    rule BWA:
        input:
            infq=join(trim_dir,"{name}.R1.trim.fastq.gz"),
        params:
            d=bam_dir,
            rname='pl:bwa',
            reference=config['references'][pfamily]['BWA'],
            reflen=config['references'][pfamily]['REFLEN'],
            bwaver=config['bin'][pfamily]['BWAVER'],
            samtoolsver=config['bin'][pfamily]['SAMTOOLSVER'],
        output:
            outbam1="{d}/{name}.sorted.bam", 
            outbam2="{d}/{name}.sorted.mapq_gt_3.bam",
            flagstat1="{d}/{name}.sorted.bam.flagstat",
            flagstat2="{d}/{name}.sorted.mapq_gt_3.bam.flagstat",
        threads: 32
        shell: 
            """
module load {params.bwaver};
module load {params.samtoolsver};
bwa mem -t {threads} {params.reference} {input} | \
samtools sort -@{threads} -o {output.outbam1}
samtools index {output.outbam1}
samtools flagstat {output.outbam1} > {output.flagstat1}
samtools view -b -q 4 {output.outbam1} -o {output.outbam2}
samtools index {output.outbam2}
samtools flagstat {output.outbam2} > {output.flagstat2}
            """  
                
    rule preseq:
        params:
            rname = "pl:preseq",
            preseqver=config['bin'][pfamily]['PRESEQVER'],
        input:
            bam = join(bam_dir,"{name}.sorted.bam"),
        output:
            ccurve = join(preseq_dir,"{name}.ccurve"),
        shell:
            """
module load {params.preseqver};
preseq c_curve -B -o {output.ccurve} {input.bam}            
            """
            
    rule picard_dedup:
        input: 
            bam1= join(bam_dir,"{name}.sorted.bam"),
            bam2= join(bam_dir,"{name}.sorted.mapq_gt_3.bam")
        output:
            out1=temp(join(bam_dir,"{name}.bwa_rg_added.sorted.bam")), 
            out2=join(bam_dir,"{name}.sorted.dedup.bam"),
            out2f=join(bam_dir,"{name}.sorted.dedup.bam.flagstat"),
            out3=join(bam_dir,"{name}.bwa.duplic"), 
            out4=temp(join(bam_dir,"{name}.bwa_rg_added.sorted.mapq_gt_3.bam")), 
            out5=join(bam_dir,"{name}.sorted.mapq_gt_3.dedup.bam"),
            out5f=join(bam_dir,"{name}.sorted.mapq_gt_3.dedup.bam.flagstat"),
            out6=join(bam_dir,"{name}.bwa.mapq_gt_3.duplic"), 
        params:
            rname='pl:dedup',
            batch='--mem=24g --time=10:00:00 --gres=lscratch:800',
            picardver=config['bin'][pfamily]['PICARDVER'],
            samtoolsver=config['bin'][pfamily]['SAMTOOLSVER'],
        shell: 
            """
module load {params.samtoolsver};
module load {params.picardver}; 
java -Xmx10g \
  -jar $PICARDJARPATH/AddOrReplaceReadGroups.jar \
  INPUT={input.bam1} \
  OUTPUT={output.out1} \
  TMP_DIR=/lscratch/$SLURM_JOBID \
  RGID=id \
  RGLB=library \
  RGPL=illumina \
  RGPU=machine \
  RGSM=sample; 
java -Xmx10g \
  -jar $PICARDJARPATH/MarkDuplicates.jar \
  INPUT={output.out1} \
  OUTPUT={output.out2} \
  TMP_DIR=/lscratch/$SLURM_JOBID \
  CREATE_INDEX=true \
  VALIDATION_STRINGENCY=SILENT \
  REMOVE_DUPLICATES=true \
  METRICS_FILE={output.out3}
samtools flagstat {output.out2} > {output.out2f}
java -Xmx10g \
  -jar $PICARDJARPATH/AddOrReplaceReadGroups.jar \
  INPUT={input.bam2} \
  OUTPUT={output.out4} \
  TMP_DIR=/lscratch/$SLURM_JOBID \
  RGID=id \
  RGLB=library \
  RGPL=illumina \
  RGPU=machine \
  RGSM=sample; 
java -Xmx10g \
  -jar $PICARDJARPATH/MarkDuplicates.jar \
  INPUT={output.out4} \
  OUTPUT={output.out5} \
  TMP_DIR=/lscratch/$SLURM_JOBID \
  CREATE_INDEX=true \
  VALIDATION_STRINGENCY=SILENT \
  REMOVE_DUPLICATES=true \
  METRICS_FILE={output.out6}
samtools flagstat {output.out5} > {output.out5f}
            """

#     rule bam2bw_prep:
#         params:
#             rname="pl:bam2bw_prep",
#         input:
#             bam=expand(join(bam_dir,"{name}.{ext}.bam"),name=samples,ext=extensions2),
#             flagstat=expand(join(bam_dir,"{name}.{ext}.bam.flagstat"),name=samples,ext=extensions2),
#         output:
#             expand(join(bam_dir,"{ext}.bam2bw_prep"),ext=extensions2),
#         run:
#             for x in extensions2:
#                  o=open(join(bam_dir,x+".bam2bw_prep"),'w')
#                  outbg=re.sub(".bam.flagstat",".normalized.bg",input.flagstat)
#                  outbw=re.sub(".bam.flagstat",".normalized.bw",input.flagstat)
#                  o.write("%s\t%s\t%s\t%s"%(input.bam,input.flagstat,outbg,outbw))
#                  o.close()
                                    
    rule bam2bw:
        input:
            bam1= join(bam_dir,"{name}.sorted.bam"),
            bam2= join(bam_dir,"{name}.sorted.mapq_gt_3.bam"),
            flagstat1=join(bam_dir,"{name}.sorted.bam.flagstat"),
            flagstat2=join(bam_dir,"{name}.sorted.mapq_gt_3.bam.flagstat"),
            bam3= join(bam_dir,"{name}.sorted.dedup.bam"),
            bam4= join(bam_dir,"{name}.sorted.mapq_gt_3.dedup.bam"),
            flagstat3=join(bam_dir,"{name}.sorted.dedup.bam.flagstat"),
            flagstat4=join(bam_dir,"{name}.sorted.mapq_gt_3.dedup.bam.flagstat"),
        output:
            outbg1=temp(join(bw_dir,"{name}.sorted.normalized.bg")), 
            outbg2=temp(join(bw_dir,"{name}.sorted.mapq_gt_3.normalized.bg")),
            outbw1=join(bw_dir,"{name}.sorted.normalized.bw"), 
            outbw2=join(bw_dir,"{name}.sorted.mapq_gt_3.normalized.bw"),
            outbg3=temp(join(bw_dir,"{name}.sorted.dedup.normalized.bg")), 
            outbg4=temp(join(bw_dir,"{name}.sorted.mapq_gt_3.dedup.normalized.bg")),
            outbw3=join(bw_dir,"{name}.sorted.dedup.normalized.bw"), 
            outbw4=join(bw_dir,"{name}.sorted.mapq_gt_3.dedup.normalized.bw"),
        params:
            rname="pl:bam2bw",
            batch='--mem=24g --time=10:00:00 --gres=lscratch:800',
            reflen=config['references'][pfamily]['REFLEN'],
            bedtoolsver=config['bin'][pfamily]['BEDTOOLSVER'],
            ucscver=config['bin'][pfamily]['UCSCVER'],
        run:
            commoncmd="module load {params.bedtoolsver};module load {params.ucscver};"
            scale1=str(1000000000/int(list(filter(lambda x:x[3]=="mapped",list(map(lambda x:x.strip().split(),open(input.flagstat1).readlines()))))[0][0]))
            cmd1=commoncmd+"bedtools genomecov -ibam "+input.bam1+" -bg -scale "+scale1+" -g "+params.reflen+" > "+output.outbg1+" && wigToBigWig -clip "+output.outbg1+" "+params.reflen+" "+output.outbw1
            shell(cmd1)
            scale2=str(1000000000/int(list(filter(lambda x:x[3]=="mapped",list(map(lambda x:x.strip().split(),open(input.flagstat2).readlines()))))[0][0]))
            cmd2=commoncmd+"bedtools genomecov -ibam "+input.bam2+" -bg -scale "+scale2+" -g "+params.reflen+" > "+output.outbg2+" && wigToBigWig -clip "+output.outbg2+" "+params.reflen+" "+output.outbw2
            shell(cmd2)
            scale3=str(1000000000/int(list(filter(lambda x:x[3]=="mapped",list(map(lambda x:x.strip().split(),open(input.flagstat3).readlines()))))[0][0]))
            cmd3=commoncmd+"bedtools genomecov -ibam "+input.bam3+" -bg -scale "+scale3+" -g "+params.reflen+" > "+output.outbg3+" && wigToBigWig -clip "+output.outbg3+" "+params.reflen+" "+output.outbw3
            shell(cmd3)
            scale4=str(1000000000/int(list(filter(lambda x:x[3]=="mapped",list(map(lambda x:x.strip().split(),open(input.flagstat4).readlines()))))[0][0]))
            cmd4=commoncmd+"bedtools genomecov -ibam "+input.bam4+" -bg -scale "+scale4+" -g "+params.reflen+" > "+output.outbg4+" && wigToBigWig -clip "+output.outbg4+" "+params.reflen+" "+output.outbw4
            shell(cmd4)


    rule deeptools_prep:
        input:
            expand(join(bw_dir,"{name}.{ext}.bw"),name=samples,ext=extensions),
        output:
            expand(join(bw_dir,"{ext}.deeptools_prep"),ext=extensions),
        params:
            rname="pl:deeptools_prep",
            batch="--mem=10g --time=1:00:00",
        threads: 1
        run:
            for x in extensions:
                bws=list(filter(lambda z:z.endswith(x+".bw"),input))
                labels=list(map(lambda z:re.sub(bw_dir+"/","",z),list(map(lambda z:re.sub("."+x+".bw","",z),bws))))
                o=open(join(bw_dir,x+".deeptools_prep"),'w')
                o.write("%s\n"%(x))
                o.write("%s\n"%(" ".join(bws)))
                o.write("%s\n"%(" ".join(labels)))
                o.close()            


    rule deeptools:
        input:
            join(bw_dir,"{ext}.deeptools_prep"),
        output:
            join(deeptools_dir,"spearman_heatmap.{ext}.pdf"),
            join(deeptools_dir,"pearson_heatmap.{ext}.pdf"),
            join(deeptools_dir,"spearman_scatterplot.{ext}.pdf"),
            join(deeptools_dir,"pearson_scatterplot.{ext}.pdf"),
            join(deeptools_dir,"pca.{ext}.pdf"),        
        params:
            rname="pl:deeptools",
            deeptoolsver=config['bin'][pfamily]['DEEPTOOLSVER'],
        threads: 32
        run:
            import re
            commoncmd="module load {params.deeptoolsver};"
            listfile=list(map(lambda z:z.strip().split(),open(input[0],'r').readlines()))
            ext=listfile[0][0]
            bws=listfile[1]
            labels=listfile[2]
            cmd="multiBigwigSummary bins -b "+" ".join(bws)+" -l "+" ".join(labels)+" -out "+join(deeptools_dir,ext+".npz")
            shell(commoncmd+cmd)
            for cm in ["spearman", "pearson"]:
                for pt in ["heatmap", "scatterplot"]:
                    cmd="plotCorrelation -in "+join(deeptools_dir,ext+".npz")+" -o "+join(deeptools_dir,cm+"_"+pt+"."+ext+".pdf")+" -c "+cm+" -p "+pt+" --skipZeros --removeOutliers"
                    if pt=="heatmap":
                        cmd+=" --plotNumbers"
                    shell(commoncmd+cmd)
            cmd="plotPCA -in "+join(deeptools_dir,ext+".npz")+" -o "+join(deeptools_dir,"pca."+ext+".pdf")
            shell(commoncmd+cmd)
#             shell("rm -rf "+input[0])

    rule NGSPLOT:
        input:
            bam= join(bam_dir,"{name}.bam"),
        output:
            tssmax=join(ngsplot_dir,"{name}.tss.max.heatmap.pdf"),
            tsskm=join(ngsplot_dir,"{name}.tss.km.heatmap.pdf"),
            tesmax=join(ngsplot_dir,"{name}.tes.max.heatmap.pdf"),
            teskm=join(ngsplot_dir,"{name}.tes.km.heatmap.pdf"),
            genebodymax=join(ngsplot_dir,"{name}.genebody.max.heatmap.pdf"),
            genebodykm=join(ngsplot_dir,"{name}.genebody.km.heatmap.pdf"),
        params:
            rname="pl:ngsplot",
            batch='--mem=48g --time=10:00:00 --gres=lscratch:800',
            genome = config['project']['annotation'],
            ngsplotver = config['bin'][pfamily]['NGSPLOTVER'],
        threads: 32
        shell:
            """
            sh Scripts/plotngsplot.sh {params.ngsplotver} {input.bam} {params.genome}
            """               

    rule ppqt:
        input:
            bam1= join(bam_dir,"{name}.sorted.bam"),
            bam2= join(bam_dir,"{name}.sorted.mapq_gt_3.bam"),
            bam3= join(bam_dir,"{name}.sorted.dedup.bam"),
            bam4= join(bam_dir,"{name}.sorted.mapq_gt_3.dedup.bam"),
        output:
            ppqt1= join(bam_dir,"{name}.sorted.ppqt"),
            pdf1= join(bam_dir,"{name}.sorted.pdf"),
            ppqt2= join(bam_dir,"{name}.sorted.mapq_gt_3.ppqt"),
            pdf2= join(bam_dir,"{name}.sorted.mapq_gt_3.pdf"),
            ppqt3= join(bam_dir,"{name}.sorted.dedup.ppqt"),
            pdf3= join(bam_dir,"{name}.sorted.dedup.pdf"),
            ppqt4= join(bam_dir,"{name}.sorted.mapq_gt_3.dedup.ppqt"),
            pdf4= join(bam_dir,"{name}.sorted.mapq_gt_3.dedup.pdf"),
        params:
            rname="pl:ppqt",
            batch='--mem=24g --time=10:00:00 --gres=lscratch:800',
            samtoolsver=config['bin'][pfamily]['SAMTOOLSVER'],
            rver=config['bin'][pfamily]['RVER'],
        shell:
            """
            module load {params.samtoolsver};
            module load {params.rver};
            Rscript Scripts/phantompeakqualtools/run_spp.R \
            -c={input.bam1} -savp -out={output.ppqt1} 
            Rscript Scripts/phantompeakqualtools/run_spp.R \
            -c={input.bam2} -savp -out={output.ppqt2} 
            Rscript Scripts/phantompeakqualtools/run_spp.R \
            -c={input.bam3} -savp -out={output.ppqt3} 
            Rscript Scripts/phantompeakqualtools/run_spp.R \
            -c={input.bam4} -savp -out={output.ppqt4} 
            """


    rule shiftstats:
        input: 
            if1 = "{name}.sorted.bam",
            if2 = "{name}.sorted.rmdup.bam" 
        output:
            of1 = "{name}.shifts",
            of2 = "{name}.rmdup.shifts"
        params:
            rname='pl:shiftstats',
            batch='--mem=24g --time=10:00:00 --gres=lscratch:800'
        shell: 
             """
             touch {output.of1}
             touch {output.of2}
             """

    rule stats:
        input:
            file1= "{name}.bwa_rg_added.sorted.dmark.bam"
        output:
            outstar2="{name}.flagstat.concord.txt" 
        params: 
            rname='pl:stats',
            batch='--mem=24g --time=10:00:00 --gres=lscratch:800',
            picardver=config['bin'][pfamily]['PICARDVER'],
        shell:
            """
            module load samtools/1.5; 
            samtools flagstat {input.file1} > {output.outstar2}; 
            echo 0 >> {output.outstar2};
            echo 0 >> {output.outstar2};
            #samtools view -f 0x2 {input.file1} | wc -l >>{output.outstar2}; 
            #samtools view {input.file1} | grep -w -c NH:i:1  >>{output.outstar2}
            """
            
    rule multiqc:
        input: 
            expand(join(bam_dir,"{name}.bwa.duplic"), name=samples),
            expand("FQscreen/{name}.R1.trim_screen.txt",name=samples),
            expand(join(preseq_dir,"{name}.ccurve"), name=samples),
            "QC",
            "rawQC",
#             expand("{name}.flagstat.concord.txt",name=samples),
            #rules.fastq_screen.output,
            #rules.picard.output,
            #rules.trimgalore.output,
            #rules.fastqc.output,
            #rules.stats.output,

            
        output:
            "Reports/multiqc_report.html"
        params:
            rname="pl:multiqc",
            multiqc=config['bin'][pfamily]['MULTIQC'],
        threads: 1
        shell:  """
                module load {params.multiqc}
                cd Reports && multiqc -f ../
                """

elif readtype == 'Paired' :
    rule all:
        params: 
            batch='--time=168:00:00'
        input: 
            config['project']['id']+"_"+config['project']['flowcellid']+".xlsx",
            "Reports/multiqc_report.html",
            expand("{name}.RnaSeqMetrics.txt",name=samples),
            "rawQC",
            "QC",
            expand("FQscreen/{name}.R1_screen.txt",name=samples),
            expand("FQscreen/{name}.R1_screen.png",name=samples),
            expand("FQscreen/{name}.R2_screen.txt",name=samples),
            expand("FQscreen/{name}.R2_screen.png",name=samples),
            expand("{name}.InsertSizeMetrics.txt",name=samples) 


    rule fastq_screen:
        input: 
            "{name}.R1.fastq.gz",
            "{name}.R2.fastq.gz"
        output:
            "FQscreen/{name}.R1_screen.txt",
            "FQscreen/{name}.R1_screen.png",
            "FQscreen/{name}.R2_screen.txt",
            "FQscreen/{name}.R2_screen.png" 
        params: 
            rname='pl:fqscreen',
            fastq_screen=config['bin'][pfamily]['FASTQ_SCREEN'],
            outdir = "FQscreen",
            config=config['references'][pfamily]['FASTQ_SCREEN_CONFIG'] 
        threads: 24
        shell:
            """
            module load bowtie/2-2.3.2; 
            {params.fastq_screen} --conf {params.config} \
                --outdir {params.outdir} --subset 1000000 \
                --aligner bowtie2 --force {input}
            """

    rule rawfastqc:
        input: 
            expand("{name}.R1.fastq.gz", name=samples), 
            expand("{name}.R2.fastq.gz", name=samples)
        output: 
            "rawQC"
        priority: 2
        params: 
            rname='pl:rawfastqc',
            batch='--cpus-per-task=32 --mem=110g --time=48:00:00',
            fastqcver=config['bin'][pfamily]['FASTQCVER']
        threads: 32
        shell: 
            """
            mkdir -p {output};
            module load {params.fastqcver}; 
            fastqc {input} -t {threads} -o {output}
            """


    rule trimmomatic_pe:
        input: 
            file1= join(workpath, "{name}.R1."+filetype),
            file2= join(workpath, "{name}.R2."+filetype),
        output:
            out11="trim/{name}_R1_001_trim_paired.fastq.gz",
            out12="trim/{name}_R1_001_trim_unpaired.fastq.gz",
            out21="trim/{name}_R2_001_trim_paired.fastq.gz",
            out22="trim/{name}_R2_001_trim_unpaired.fastq.gz",
            err="QC/{name}_run_trimmomatic.err"
        params:
            rname='pl:trimmomatic_pe',
            batch='--cpus-per-task=32 --mem=110g --time=48:00:00',
            trimmomaticver=config['bin'][pfamily]['TRIMMOMATICVER'],
            fastawithadaptersetc=config['references'][pfamily]['FASTAWITHADAPTERSETC'],
            seedmismatches=config['bin'][pfamily]['SEEDMISMATCHES'],
            palindromeclipthreshold=config['bin'][pfamily]['PALINDROMECLIPTHRESHOLD'],
            simpleclipthreshold=config['bin'][pfamily]['SIMPLECLIPTHRESHOLD'],
            leadingquality=config['bin'][pfamily]['LEADINGQUALITY'],
            trailingquality=config['bin'][pfamily]['TRAILINGQUALITY'],
            windowsize=config['bin'][pfamily]['WINDOWSIZE'],
            windowquality=config['bin'][pfamily]['WINDOWQUALITY'],
            targetlength=config['bin'][pfamily]['TARGETLENGTH'],
            strictness=config['bin'][pfamily]['STRICTNESS'],
            minlen=config['bin'][pfamily]['MINLEN'],
            headcroplength=config['bin'][pfamily]['HEADCROPLENGTH']
        threads:32
        shell:
            """
            module load {params.trimmomaticver}; 
            java -classpath $TRIMMOJAR   org.usadellab.trimmomatic.TrimmomaticPE \
                 -threads {threads} {input.file1} {input.file2} \
                          {output.out11} {output.out12} {output.out21} {output.out22} \
                 ILLUMINACLIP:{params.fastawithadaptersetc}:{params.seedmismatches}:{params.palindromeclipthreshold}:{params.simpleclipthreshold} 2> {output.err}
            """

    rule fastqc:  
        input:
            expand("trim/{name}_R1_001_trim_paired.fastq.gz", name=samples),
            expand("trim/{name}_R2_001_trim_paired.fastq.gz", name=samples)  
        output: "QC"
        priority: 2
        params: 
            rname='pl:fastqc',
            batch='--cpus-per-task=32 --mem=110g --time=48:00:00',
            fastqcver=config['bin'][pfamily]['FASTQCVER']
        threads: 32
        shell: 
            """
            mkdir -p {output};
            module load {params.fastqcver}; 
            fastqc {input} -t {threads} -o {output}
            """

    rule bwa:
        input:
            file1= "trim/{name}_R1_001_trim_paired.fastq.gz",
            file2="trim/{name}_R2_001_trim_paired.fastq.gz"
        output:
            out= "{name}.p2.Aligned.sortedByCoord.out.bam"
        params:
            rname='pl:bwa',
            prefix="{name}",
            batch='--cpus-per-task=32 --mem=32g --time=48:00:00',
            reference= config['references'][pfamily]['BWA'],
        threads: 32
        shell: 
            """
            module load bwa;
            bwa mem -t  {threads} {params.reference} {file1} {file2} | samtools sort -o {out}
            """  

    rule picard:
        input: 
            file1= "{name}.p2.Aligned.sortedByCoord.out.bam"
        output:
            outstar1=temp("{name}.star_rg_added.sorted.bam"), 
            outstar2="{name}.star_rg_added.sorted.dmark.bam",
            outstar3="{name}.star.duplic" 
        params:
            rname='pl:picard',
            batch='--mem=24g --time=10:00:00 --gres=lscratch:800',
            picardver=config['bin'][pfamily]['PICARDVER']
        shell: 
             """
             module load {params.picardver}; 
             java -Xmx10g \
                  -jar $PICARDJARPATH/AddOrReplaceReadGroups.jar \
                  INPUT={input.file1} \
                  OUTPUT={output.outstar1} \
                  TMP_DIR=/lscratch/$SLURM_JOBID \
                  RGID=id \
                  RGLB=library \
                  RGPL=illumina \
                  RGPU=machine \
                  RGSM=sample; 
             java -Xmx10g \
                  -jar $PICARDJARPATH/MarkDuplicates.jar \
                  INPUT={output.outstar1} \
                  OUTPUT={output.outstar2} \
                  TMP_DIR=/lscratch/$SLURM_JOBID \
                  CREATE_INDEX=true \
                  VALIDATION_STRINGENCY=SILENT \
                  METRICS_FILE={output.outstar3}
             """

    rule stats:
        input:
            file1= "{name}.star_rg_added.sorted.dmark.bam"
        output:
            outstar1="{name}.RnaSeqMetrics.txt",
            outstar2="{name}.flagstat.concord.txt", 
            outstar3="{name}.InsertSizeMetrics.txt", 
            outstar4="{name}.InsertSizeHisto.pdf"
        params: 
            rname='pl:stats',
            batch='--mem=24g --time=10:00:00 --gres=lscratch:800',
            picardver=config['bin'][pfamily]['PICARDVER'],
        shell:
            """
            module load R/3.4.0_gcc-6.2.0;
            module load {params.picardver};
            java -Xmx10g \
                 -jar $PICARDJARPATH/CollectRnaSeqMetrics.jar \
                 INPUT={input.file1} \
                 OUTPUT={output.outstar1} \
                 TMP_DIR=/lscratch/$SLURM_JOBID  \
                 VALIDATION_STRINGENCY=SILENT ; 
            java -Xmx10g \
                 -jar $PICARDJARPATH/CollectInsertSizeMetrics.jar \
                 INPUT={input.file1} \
                 OUTPUT={output.outstar3} \
                 HISTOGRAM_FILE={output.outstar4} \
                 MINIMUM_PCT=0.5 \
                 TMP_DIR=/lscratch/$SLURM_JOBID ;

            module load samtools; 
            samtools flagstat {input.file1} > {output.outstar2}; 
            samtools view -f 0x2 {input.file1} | wc -l >>{output.outstar2}; 
            samtools view {input.file1} | grep -w -c NH:i:1  >>{output.outstar2}
            """


    rule rnaseq_multiqc:
        input: 
            expand("{name}.Rdist.info",name=samples),
            expand("FQscreen/{name}.R1_screen.png",name=samples),
            expand("FQscreen/{name}.R2_screen.png",name=samples),
            expand("{name}.flagstat.concord.txt",name=samples),
            expand("{name}.RnaSeqMetrics.txt",name=samples),
            expand("{name}.InsertSizeMetrics.txt",name=samples)
        output:
            "Reports/multiqc_report.html"
        params:
            rname="pl:multiqc",
            multiqc=config['bin'][pfamily]['MULTIQC'],
        threads: 1
        shell:  """
                module load {params.multiqc}
                cd Reports && multiqc -f  ../
                """

    rule RNAseq_generate_QC_table:
        input:
            expand("QC/{name}_run_trimmomatic.err",name=samples),
            expand("{name}.star.duplic",name=samples),
            expand("{name}.p2.Log.final.out",name=samples),
            expand("{name}.RnaSeqMetrics.txt",name=samples)
        output:
            config['project']['id']+"_"+config['project']['flowcellid']+".xlsx"
        params:
            workpath,
            project=config['project']['id'],
            flowcell=config['project']['flowcellid'],
            rname="pl:QC_table"
        shell: 
            """
            perl Scripts/CollectPipelineStats2Tab_v2.3.pl \
                -p {params.project}\
                -f {params.flowcell}\
                -d {params.workpath}\
                -r 5\
                -e 2;
            perl Scripts/Tab2Excel_v2.3.pl -i {params.project}_{params.flowcell} -r 5
            """


