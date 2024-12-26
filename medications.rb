# required == interval => TAKE
# required >  interval => Optl to TAKE
#
MEDS[:morphine_er]       = Med.new(name: :morphine_er,    interval:7.5,  required:8.5,default_dose:15,   half_life:3.5*3600,   max_dose:0,     dose_units: :mg,   display: :yes,      display_log:true,  announce:false,   emoji:"1F480")
MEDS[:morphine_ir]       = Med.new(name: :morphine_ir,    interval:4,    required:5,  default_dose:15,   half_life:3.5*3600,   max_dose:0,     dose_units: :mg,   display: :on_dose,  display_log:true,  announce:false,  emoji:"1F480")
MEDS[:morphine_bt]       = Med.new(name: :morphine_bt,    interval:8,    required:5,  default_dose:7.5,  half_life:3*3600,     max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F48A")
MEDS[:oxycodone]         = Med.new(name: :oxycodone,      interval:4,    required:5,  default_dose:5,    half_life:3*3600,     max_dose:0,     dose_units: :mg,   display: :on_dose,  display_log:true,  announce:false,  emoji:"1F48A")
MEDS[:hydrocodone]       = Med.new(name: :hydrocodone,    interval:4,    required:48, default_dose:10,   half_life:3.8*3600,   max_dose:0,     dose_units: :mg,   display: :on_dose,  display_log:true,  announce:false,  emoji:"1F48A")
MEDS[:dilauded]          = Med.new(name: :dilauded,       interval:4,    required:6,  default_dose:1,    half_life:2.5*3600,   max_dose:0,     dose_units: :mg,   display: :on_dose,  display_log:true,  announce:false,  emoji:"1F48A")
MEDS[:baclofen]          = Med.new(name: :baclofen,       interval:23.9, required:48, default_dose:5,    half_life:4*3600,     max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"26A1")
MEDS[:robaxin]           = Med.new(name: :robaxin,        interval:2,    required:10, default_dose:500,  half_life:1.1*3600,   max_dose:0,     dose_units: :mg,   display: :no,       display_log:true,  announce:false,  emoji:"26A1")
MEDS[:lyrica]            = Med.new(name: :lyrica,         interval:10,   required:18, default_dose:18,   half_life:6.3*3600,   max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F9E0")
MEDS[:periactin]         = Med.new(name: :periactin,      interval:6,    required:8,  default_dose:2,    half_life:7.5*3600,   max_dose:12,    dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F971")

MEDS[:esgic]             = Med.new(name: :esgic,          interval:4,    required:48, default_dose:1,    half_life:35*3600,    max_dose:0,     dose_units: :unit, display: :yes,      display_log:true,  announce:false,  emoji:"1F915")
MEDS[:tylenol]           = Med.new(name: :tylenol,        interval:4,    required:96, default_dose:500,  half_life:3*3600,     max_dose:0,     dose_units: :mg,   display: :yes,      display_log:true,  announce:false,  emoji:"1F915")
MEDS[:xanax]             = Med.new(name: :xanax,          interval:4,    required:48, default_dose:0.25, half_life:6*3600,     max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F630")
MEDS[:phenergan]         = Med.new(name: :phenergan,      interval:4,    required:48, default_dose:25,   half_life:14.5*3600,  max_dose:0,     dose_units: :mg,   display: :no,       display_log:true,  announce:false,  emoji:"1F48A")
MEDS[:propranolol]       = Med.new(name: :propranolol,    interval:4,    required:48, default_dose:80,   half_life:5*3600,     max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F497")
MEDS[:ondansetron]       = Med.new(name: :ondansetron,    interval:4,    required:48, default_dose:4,    half_life:4*3600,     max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F48A")
MEDS[:soma]              = Med.new(name: :soma,           interval:4,    required:48, default_dose:350,  half_life:2*3600,     max_dose:0,     dose_units: :mg,   display: :on_dose,  display_log:false, announce:false,  emoji:"1F48A")
MEDS[:lansoprazole]      = Med.new(name: :lansoprazole,   interval:24,   required:24, default_dose:15,   half_life:1.7*3600,   max_dose:15,    dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F48A")
MEDS[:taurine]           = Med.new(name: :taurine,        interval:4,    required:6,  default_dose:500,  half_life:3600,       max_dose:6500,  dose_units: :mg,   display: :yes,      display_log:true,  announce:false,  emoji:"1F431")
MEDS[:calcium]           = Med.new(name: :calcium,        interval:4,    required:6,  default_dose:250,  half_life:2*3600,     max_dose:1750,  dose_units: :mg,   display: :yes,      display_log:true,  announce:false,  emoji:"1F9B4")
MEDS[:iron]              = Med.new(name: :iron,           interval:3,    required:4,  default_dose:10.5, half_life:5*3600,     max_dose:31.5,  dose_units: :mg,   display: :no,       display_log:true,  announce:false,  emoji:"1FA78")
MEDS[:vitamin_d]         = Med.new(name: :vitamin_d,      interval:3,    required:4,  default_dose:1000, half_life:5*24*3600,  max_dose:3000,  dose_units: :iu,   display: :no,       display_log:false, announce:false,  emoji:"1F31E")
MEDS[:plc]               = Med.new(name: :plc,            interval:24,   required:48, default_dose:500,  half_life:25.7*3600,  max_dose:2000,  dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:alcar]             = Med.new(name: :alcar,          interval:24,   required:24, default_dose:500,  half_life:4.2*3600,   max_dose:2000,  dose_units: :mg,   display: :on_dose,  display_log:false, announce:false,  emoji:"1F9B4")

MEDS[:msm]               = Med.new(name: :msm,            interval:1.75, required:2,  default_dose:500,  half_life:8*3600,    max_dose:5000,  dose_units: :mg,   display: :yes_awake, display_log:true,  announce:false,  emoji:"1F30B")
MEDS[:magnesium]         = Med.new(name: :magnesium,      interval:4,    required:6,  default_dose:48,   half_life:4*3600,    max_dose:192,   dose_units: :mg,   display: :yes_awake, display_log:true,  announce:false,  emoji:"1F33F")
MEDS[:nac]               = Med.new(name: :nac,            interval:24,   required:24, default_dose:500,  half_life:5.6*3600,  max_dose:2000,  dose_units: :mg,   display: :yes,       display_log:false, announce:false,  emoji:"26FD")
MEDS[:l_theanine]        = Med.new(name: :l_theanine,     interval:1,    required:48, default_dose:50,   half_life:1.2*3600,  max_dose:900,   dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1FAB7")
MEDS[:apigenin]          = Med.new(name: :apigenin,       interval:12,   required:48, default_dose:25,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")

MEDS[:butyrate]          = Med.new(name: :butyrate,       interval:24,   required:48, default_dose:100,  half_life:3600,      max_dose:600,   dose_units: :mg,   display: :yes,       display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:liver]             = Med.new(name: :liver,          interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:3000,  dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
MEDS[:marrow]            = Med.new(name: :marrow,         interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:3000,  dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
MEDS[:probiotic]         = Med.new(name: :probiotic,      interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:1,     dose_units: :mg,   display: :yes,       display_log:false, announce:false,  emoji:"1F48A")
MEDS[:oyster]            = Med.new(name: :oyster,         interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
MEDS[:fish_eggs]         = Med.new(name: :fish_eggs,      interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
MEDS[:juice]             = Med.new(name: :juice,          interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:0,     dose_units: :unit, display: :no,        display_log:false, announce:false,  emoji:"1F48A")
MEDS[:phospholipid_c]    = Med.new(name: :phospholipid_c, interval:24,   required:48, default_dose:1300, half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
MEDS[:phosphatidyl_c]    = Med.new(name: :phosphatidyl_c, interval:24,   required:48, default_dose:420,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F9E0")
MEDS[:epa]               = Med.new(name: :epa,            interval:24,   required:48, default_dose:1000, half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
MEDS[:dha]               = Med.new(name: :dha,            interval:24,   required:48, default_dose:1000, half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
MEDS[:famotidine]        = Med.new(name: :famotidine,     interval:4,    required:48, default_dose:20,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
MEDS[:hydroxyzine]       = Med.new(name: :hydroxyzine,    interval:4,    required:48, default_dose:25,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
MEDS[:marshmallow_r]     = Med.new(name: :marshmallow_r,  interval:24,   required:48, default_dose:200,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
# 137ug per spray, 2x per nostril = 548ug
MEDS[:azelastine]        = Med.new(name: :azelastine,     interval:24,   required:48, default_dose:548,  half_life:54*3600,   max_dose:0,     dose_units: :ug,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
# 27.5ug per spray, 2x per nostril = 100ug
MEDS[:veramyst]          = Med.new(name: :veramyst,       interval:24,   required:48, default_dose:110,  half_life:16*3600,   max_dose:0,     dose_units: :ug,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:metoclopramide]    = Med.new(name: :metoclopramide, interval:24,   required:48, default_dose:10,   half_life:5*3600,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
MEDS[:docusate]          = Med.new(name: :docusate,       interval:3,    required:3,  default_dose:100,  half_life:3600,      max_dose:300,   dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A9")
MEDS[:valerian_root]     = Med.new(name: :valerian_root,  interval:4,    required:48, default_dose:400,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4AE")
MEDS[:calcium_aep]       = Med.new(name: :calcium_aep,    interval:4,    required:48, default_dose:1850, half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4AE")
MEDS[:fem]               = Med.new(name: :fem,            interval:24,   required:24, default_dose:1,    half_life:3600,      max_dose:0,     dose_units: :unit, display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:roe]               = Med.new(name: :roe,            interval:24,   required:24, default_dose:28,   half_life:3600,      max_dose:0,     dose_units: :g,    display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:hd]                = Med.new(name: :hd,             interval:24,   required:24, default_dose:1,    half_life:3600,      max_dose:1,     dose_units: :g,    display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:phys_thr]          = Med.new(name: :phys_thr,       interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:0,     dose_units: :unit, display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:colostrum]         = Med.new(name: :colostrum,      interval:23,   required:48, default_dose:500,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:quercetin]         = Med.new(name: :quercetin,      interval:23,   required:48, default_dose:500,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:emiq]              = Med.new(name: :emiq,           interval:23,   required:48, default_dose:33,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:mirtazapine]       = Med.new(name: :mirtazapine,    interval:24,   required:48, default_dose:7.5,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:potassium]         = Med.new(name: :potassium,      interval:24,   required:48, default_dose:33,   half_life:3600,      max_dose:0,     dose_units: :meq,  display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:hesperidin]        = Med.new(name: :hesperidin,     interval:24,   required:48, default_dose:50,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:diosmin]           = Med.new(name: :diosmin,        interval:24,   required:48, default_dose:450,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:pea]               = Med.new(name: :pea,            interval:24,   required:48, default_dose:400,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:pqq]               = Med.new(name: :pqq,            interval:24,   required:48, default_dose:10,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:c60]               = Med.new(name: :c60,            interval:24,   required:48, default_dose:10,   half_life:3600,      max_dose:0,     dose_units: :unit, display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:coco]              = Med.new(name: :coco,           interval:24,   required:48, default_dose:10,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:ubiquinol]         = Med.new(name: :ubiquinol,      interval:3,    required:4.5, default_dose:50,  half_life:3600*33,   max_dose:200,   dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:biotin]            = Med.new(name: :biotin,         interval:2,    required:2,   default_dose:1,   half_life:3600,      max_dose:0,     dose_units: :unit, display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:coq10]             = Med.new(name: :coq10,          interval:3,    required:4.5, default_dose:50,  half_life:3600*33,   max_dose:200,   dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:herbs]             = Med.new(name: :herbs,          interval:4,    required:24, default_dose:1,    half_life:3600,      max_dose:0,     dose_units: :unit, display: :no,        display_log:false, announce:false,  emoji:"1F4A8")
MEDS[:ergothioneine]     = Med.new(name: :ergothioneine,  interval:4,    required:6,  default_dose:25,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:creatine]          = Med.new(name: :creatine,       interval:24,   required:24, default_dose:1,    half_life:3600*3,    max_dose:5,     dose_units: :g,    display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:dummy]             = Med.new(name: :dummy,          interval:4,    required:6,  default_dose:25,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
MEDS[:mitoq]             = Med.new(name: :mitoq,          interval:24,   required:24, default_dose:2.5,  half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:hcasein]           = Med.new(name: :hcasein,        interval:24,   required:24, default_dose:2.5,  half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:bacopa]            = Med.new(name: :bacopa,         interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:garlic]            = Med.new(name: :garlic,         interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:glycine]           = Med.new(name: :glycine,        interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:dmannose]          = Med.new(name: :dmannose,       interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:egg_lecithin]      = Med.new(name: :egg_lecithin,   interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:uroa]              = Med.new(name: :uroa,           interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:spermidine]        = Med.new(name: :spermidine,     interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:astaxanthin]       = Med.new(name: :astaxanthin,    interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:nr]                = Med.new(name: :nr,             interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:jellyfish]         = Med.new(name: :jellyfish,      interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:tocotrienols]      = Med.new(name: :tocotrienols,      interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:eggshell_membrane] = Med.new(name: :eggshell_membrane,      interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:mitoq]             = Med.new(name: :mitoq,      interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:kidney]            = Med.new(name: :kidney,      interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:inulin]            = Med.new(name: :inulin,      interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
MEDS[:metamucil]         = Med.new(name: :metamucil,      interval:24,   required:24, default_dose:50,   half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")

# additional ways to match terms
MEDS[:docusate].add_match_term("docusate sodium")
MEDS[:azelastine].add_match_term("azelastine spray")
MEDS[:veramyst].add_match_term("veramyst spray")
MEDS[:morphine_er].add_match_term("morphine (er)")
MEDS[:morphine_er].add_match_term("morphine er")
MEDS[:morphine_ir].add_match_term("morphine (ir)")
MEDS[:morphine_ir].add_match_term("morphine ir")
MEDS[:phosphatidyl_c].add_match_term("pc")
MEDS[:valerian_root].add_match_term("valerian root")
MEDS[:fish_eggs].add_match_term("fish egg")
MEDS[:calcium_aep].add_match_term("calcium aep")
MEDS[:phys_thr].add_match_term("physical")
MEDS[:phys_thr].add_match_term("physical therapy")
# frozen_string_literal: true

# 45 min pre-waking
MED_SETS.push({ interval: 0.75, label: "45 mins - pre-awakening ",
                set: [
                  { med: MEDS[:bacopa], dose: "1 unit" },
                  { med: MEDS[:mitoq], dose: "2 units" },
                ]})
MED_SETS.push({ interval: 2,    label: "0:00 waking set",
                set: [
                  { med: MEDS[:garlic], dose: "2 units" },
                  { med: MEDS[:nac], dose: "4 units" },
                  { med: MEDS[:glycine], dose: "2 units" },
                  { med: MEDS[:dmannose], dose: "4 units" },
                  { med: MEDS[:magnesium], dose: "2 units" },
                  { med: MEDS[:egg_lecithin], dose: "4 units" }
                ]})
MED_SETS.push({ interval: 4,    label: "2:00 hour set (with food)",
                set: [
                  { med: MEDS[:uroa], dose: "2 units" },
                  { med: MEDS[:alcar], dose: "4 units" },
                  { med: MEDS[:liver], dose: "4 units" },
                  { med: MEDS[:spermidine], dose: "1 unit" },
                  { med: MEDS[:astaxanthin], dose: "1 unit" },
                  { med: MEDS[:coq10], dose: "1 unit" },
                  { med: MEDS[:probiotic], dose: "1 vsl, 1 purple" },
                  { med: MEDS[:msm],  dose: "3 units" },
                ]})
MED_SETS.push({ interval: 2,    label: "6:00 hour set",
                set: [
                  { med: MEDS[:alcar], dose: "3 units" },
                  { med: MEDS[:nr], dose: "1 unit" },
                  { med: MEDS[:nac], dose: "3 units" },
                  { med: MEDS[:glycine], dose: "2 units" },
                  { med: MEDS[:calcium], dose: "2 units" },
                  { med: MEDS[:taurine], dose: "2 units" },
                  { med: MEDS[:oyster], dose: "4 units" },
                  { med: MEDS[:jellyfish], dose: "2 units" },
                ]})
MED_SETS.push({ interval: 4,    label: "8:00 hour set",
                set: [
                  { med: MEDS[:uroa], dose: "2 units" },
                  { med: MEDS[:tocotrienols], dose: "1 unit" },
                  { med: MEDS[:eggshell_membrane], dose: "2 units" },
                  { med: MEDS[:butyrate], dose: "2 units" },
                  { med: MEDS[:msm],  dose: "3 units" },
                ]})
MED_SETS.push({ interval: 4,    label: "12:00 hour set",
                set: [
                  { med: MEDS[:mitoq], dose: "1 unit" },
                  { med: MEDS[:pqq], dose: "1 unit" },
                  { med: MEDS[:ergothioneine], dose: "1 unit" },
                  { med: MEDS[:kidney], dose: "12 units" },
                  { med: MEDS[:metamucil], dose: "5 units" },
                  { med: MEDS[:magnesium], dose: "2 units" },
                  { med: MEDS[:calcium], dose: "1 unit" },
                  { med: MEDS[:taurine], dose: "1 unit" },
                ]})