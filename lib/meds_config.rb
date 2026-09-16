# frozen_string_literal: true

# Med catalog: which meds exist, dosing intervals, display flags.
# Returns a fresh hash each call (reset_meds rebuilds it on every refresh).
#
# required == interval => TAKE
# required >  interval => Optl to TAKE
module MedsConfig
  def self.build
    meds = {}
    meds[:morphine_er]    = Med.new(name: :morphine_er,    interval:7.5,  required:8.5,default_dose:15,   half_life:3.5*3600,   max_dose:0,     dose_units: :mg,   display: :on_dose,  display_log:true,  announce:false,  emoji:"1F480")
    meds[:morphine_ir]    = Med.new(name: :morphine_ir,    interval:4,    required:5,  default_dose:15,   half_life:3.5*3600,   max_dose:0,     dose_units: :mg,   display: :on_dose,  display_log:true,  announce:false,  emoji:"1F480")
    meds[:morphine_bt]    = Med.new(name: :morphine_bt,    interval:8,    required:5,  default_dose:7.5,  half_life:3*3600,     max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F48A")
    meds[:oxycodone]      = Med.new(name: :oxycodone,      interval:4,    required:96, default_dose:5,    half_life:3*3600,     max_dose:0,     dose_units: :mg,   display: :on_dose,  display_log:true,  announce:false,  emoji:"1F48A")
    meds[:hydrocodone]    = Med.new(name: :hydrocodone,    interval:4,    required:48, default_dose:10,   half_life:3.8*3600,   max_dose:0,     dose_units: :mg,   display: :on_dose,  display_log:true,  announce:false,  emoji:"1F48A")
    meds[:dilauded]       = Med.new(name: :dilauded,       interval:4,    required:6,  default_dose:1,    half_life:2.5*3600,   max_dose:0,     dose_units: :mg,   display: :on_dose,  display_log:true,  announce:false,  emoji:"1F48A")
    meds[:baclofen]       = Med.new(name: :baclofen,       interval:23.9, required:12, default_dose:5,    half_life:4*3600,     max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F535")
    meds[:robaxin]        = Med.new(name: :robaxin,        interval:2,    required:10, default_dose:500,  half_life:1.1*3600,   max_dose:0,     dose_units: :mg,   display: :on_dose,  display_log:true,  announce:false,  emoji:"26A1")
    meds[:lyrica]         = Med.new(name: :lyrica,         interval:10,   required:18, default_dose:18,   half_life:6.3*3600,   max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F9E0")
    meds[:periactin]      = Med.new(name: :periactin,      interval:6,    required:8,  default_dose:2,    half_life:7.5*3600,   max_dose:12,    dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F971")

    meds[:esgic]          = Med.new(name: :esgic,          interval:4,    required:96, default_dose:1,    half_life:35*3600,    max_dose:0,     dose_units: :unit, display: :no,       display_log:true,  announce:false,  emoji:"1F915")
    meds[:tylenol]        = Med.new(name: :tylenol,        interval:4,    required:96, default_dose:500,  half_life:3*3600,     max_dose:0,     dose_units: :mg,   display: :no,       display_log:true,  announce:false,  emoji:"1F915")
    meds[:aspirin]        = Med.new(name: :aspirin,        interval:4,    required:96, default_dose:500,  half_life:1800,       max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F915")
    meds[:xanax]          = Med.new(name: :xanax,          interval:4,    required:96, default_dose:0.25, half_life:6*3600,     max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F630")
    meds[:phenergan]      = Med.new(name: :phenergan,      interval:4,    required:48, default_dose:25,   half_life:14.5*3600,  max_dose:0,     dose_units: :mg,   display: :no,       display_log:true,  announce:false,  emoji:"1F48A")
    meds[:propranolol]    = Med.new(name: :propranolol,    interval:4,    required:48, default_dose:80,   half_life:5*3600,     max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F497")
    meds[:ondansetron]    = Med.new(name: :ondansetron,    interval:4,    required:48, default_dose:4,    half_life:4*3600,     max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F48A")
    meds[:soma]           = Med.new(name: :soma,           interval:4,    required:48, default_dose:350,  half_life:2*3600,     max_dose:0,     dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F48A")
    meds[:lansoprazole]   = Med.new(name: :lansoprazole,   interval:24,   required:24, default_dose:15,   half_life:1.7*3600,   max_dose:15,    dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F48A")

    meds[:cdp]            = Med.new(name: :cdp,            interval:4,    required:48, default_dose:420,  half_life:3*86400,    max_dose:0,     dose_units: :mg,   display: :yes,       display_log:true,  announce:false,  emoji:"26A1")
    meds[:phosphatidyl_c] = Med.new(name: :phosphatidyl_c, interval:4,    required:48, default_dose:420,  half_life:24*3600,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:true,  announce:false,  emoji:"1F9E0")
    meds[:choline_b]      = Med.new(name: :choline_b,      interval:6.5,  required:6.5,default_dose:6.25, half_life:10*3600,    max_dose:0,     dose_units: :mg,   display: :yes,       display_log:true,  announce:false,  emoji:"1F971")

    meds[:taurine]        = Med.new(name: :taurine,        interval:4,    required:96, default_dose:500,  half_life:3600,       max_dose:6500,  dose_units: :mg,   display: :yes,      display_log:true,  announce:false,  emoji:"1F431")
    meds[:calcium]        = Med.new(name: :calcium,        interval:4,    required:96, default_dose:250,  half_life:2*3600,     max_dose:1750,  dose_units: :mg,   display: :yes,      display_log:true,  announce:false,  emoji:"1F9B4")
    meds[:iron]           = Med.new(name: :iron,           interval:3,    required:4,  default_dose:10.5, half_life:5*3600,     max_dose:31.5,  dose_units: :mg,   display: :no,       display_log:true,  announce:false,  emoji:"1FA78")
    meds[:vitamin_d]      = Med.new(name: :vitamin_d,      interval:3,    required:4,  default_dose:1000, half_life:5*24*3600,  max_dose:3000,  dose_units: :iu,   display: :no,       display_log:false, announce:false,  emoji:"1F31E")
    meds[:plc]            = Med.new(name: :plc,            interval:24,   required:48, default_dose:500,  half_life:25.7*3600,  max_dose:2000,  dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F4A6")
    meds[:alcar]          = Med.new(name: :alcar,          interval:24,   required:24, default_dose:500,  half_life:4.2*3600,   max_dose:2000,  dose_units: :mg,   display: :no,       display_log:false, announce:false,  emoji:"1F9B4")

    meds[:msm]            = Med.new(name: :msm,            interval:1.75, required:2,  default_dose:500,  half_life:8*3600,    max_dose:5000,  dose_units: :mg,   display: :no,        display_log:true,  announce:false,  emoji:"1F30B")
    meds[:magnesium]      = Med.new(name: :magnesium,      interval:4,    required:96, default_dose:48,   half_life:4*3600,    max_dose:192,   dose_units: :mg,   display: :yes,       display_log:true,  announce:false,  emoji:"1F33F")
    meds[:nac]            = Med.new(name: :nac,            interval:6,    required:24, default_dose:500,  half_life:5.6*3600,  max_dose:2000,  dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"26FD")
    meds[:l_theanine]     = Med.new(name: :l_theanine,     interval:1,    required:48, default_dose:50,   half_life:1.2*3600,  max_dose:900,   dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1FAB7")
    meds[:apigenin]       = Med.new(name: :apigenin,       interval:12,   required:48, default_dose:25,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")

    meds[:butyrate]       = Med.new(name: :butyrate,       interval:24,   required:48, default_dose:100,  half_life:3600,      max_dose:600,   dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:liver]          = Med.new(name: :liver,          interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:3000,  dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
    meds[:marrow]         = Med.new(name: :marrow,         interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:3000,  dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
    meds[:probiotic]      = Med.new(name: :probiotic,      interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:1,     dose_units: :mg,   display: :yes,       display_log:false, announce:false,  emoji:"1F48A")
    meds[:oyster]         = Med.new(name: :oyster,         interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:0,     dose_units: :mg,   display: :yes,        display_log:false, announce:false,  emoji:"1F48A")
    meds[:fish_eggs]      = Med.new(name: :fish_eggs,      interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
    meds[:juice]          = Med.new(name: :juice,          interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:0,     dose_units: :unit, display: :no,        display_log:false, announce:false,  emoji:"1F48A")
    meds[:phospholipid_c] = Med.new(name: :phospholipid_c, interval:24,   required:48, default_dose:1300, half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
    meds[:epa]            = Med.new(name: :epa,            interval:24,   required:48, default_dose:1000, half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
    meds[:dha]            = Med.new(name: :dha,            interval:24,   required:48, default_dose:1000, half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
    meds[:famotidine]     = Med.new(name: :famotidine,     interval:4,    required:48, default_dose:20,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
    meds[:hydroxyzine]    = Med.new(name: :hydroxyzine,    interval:4,    required:48, default_dose:25,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
    meds[:marshmallow_r]  = Med.new(name: :marshmallow_r,  interval:24,   required:48, default_dose:200,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
    # 137ug per spray, 2x per nostril = 548ug
    meds[:azelastine]     = Med.new(name: :azelastine,     interval:24,   required:48, default_dose:548,  half_life:54*3600,   max_dose:0,     dose_units: :ug,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    # 27.5ug per spray, 2x per nostril = 100ug
    meds[:veramyst]       = Med.new(name: :veramyst,       interval:24,   required:48, default_dose:110,  half_life:16*3600,   max_dose:0,     dose_units: :ug,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:metoclopramide] = Med.new(name: :metoclopramide, interval:24,   required:48, default_dose:10,   half_life:5*3600,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F48A")
    meds[:docusate]       = Med.new(name: :docusate,       interval:3,    required:3,  default_dose:100,  half_life:3600,      max_dose:300,   dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A9")
    meds[:valerian_root]  = Med.new(name: :valerian_root,  interval:4,    required:48, default_dose:400,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4AE")
    meds[:calcium_aep]    = Med.new(name: :calcium_aep,    interval:4,    required:48, default_dose:1850, half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4AE")
    meds[:fem]            = Med.new(name: :fem,            interval:24,   required:24, default_dose:1,    half_life:3600,      max_dose:0,     dose_units: :unit, display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:roe]            = Med.new(name: :roe,            interval:24,   required:24, default_dose:28,   half_life:3600,      max_dose:0,     dose_units: :g,    display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:hd]             = Med.new(name: :hd,             interval:24,   required:24, default_dose:1,    half_life:3600,      max_dose:1,     dose_units: :g,    display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:phys_thr]       = Med.new(name: :phys_thr,       interval:24,   required:48, default_dose:1,    half_life:3600,      max_dose:0,     dose_units: :unit, display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:colostrum]      = Med.new(name: :colostrum,      interval:23,   required:48, default_dose:500,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:quercetin]      = Med.new(name: :quercetin,      interval:23,   required:48, default_dose:500,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:emiq]           = Med.new(name: :emiq,           interval:23,   required:48, default_dose:33,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:mirtazapine]    = Med.new(name: :mirtazapine,    interval:24,   required:48, default_dose:7.5,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:potassium]      = Med.new(name: :potassium,      interval:24,   required:48, default_dose:33,   half_life:3600,      max_dose:0,     dose_units: :meq,  display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:hesperidin]     = Med.new(name: :hesperidin,     interval:24,   required:48, default_dose:50,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:diosmin]        = Med.new(name: :diosmin,        interval:24,   required:48, default_dose:450,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:pea]            = Med.new(name: :pea,            interval:24,   required:48, default_dose:400,  half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:pqq]            = Med.new(name: :pqq,            interval:24,   required:48, default_dose:10,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:c60]            = Med.new(name: :c60,            interval:24,   required:48, default_dose:10,   half_life:3600,      max_dose:0,     dose_units: :unit, display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:coco]           = Med.new(name: :coco,           interval:24,   required:48, default_dose:10,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:ubiquinol]      = Med.new(name: :ubiquinol,      interval:3,    required:4.5, default_dose:50,  half_life:3600*33,   max_dose:200,   dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
    meds[:biotin]         = Med.new(name: :biotin,         interval:2,    required:2,   default_dose:1,   half_life:3600,      max_dose:0,     dose_units: :unit, display: :no,        display_log:false, announce:false,  emoji:"1F517")
    meds[:coq10]          = Med.new(name: :coq10,          interval:3,    required:4.5, default_dose:50,  half_life:3600*33,   max_dose:200,   dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
    meds[:herbs]          = Med.new(name: :herbs,          interval:4,    required:24, default_dose:1,    half_life:3600,      max_dose:0,     dose_units: :unit, display: :no,        display_log:false, announce:false,  emoji:"1F4A8")
    meds[:ergothioneine]  = Med.new(name: :ergothioneine,  interval:4,    required:6,  default_dose:25,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:creatine]       = Med.new(name: :creatine,       interval:24,   required:24, default_dose:1,    half_life:3600*3,    max_dose:5,     dose_units: :g,    display: :no,        display_log:false, announce:false,  emoji:"1F517")
    meds[:dummy]          = Med.new(name: :dummy,          interval:4,    required:6,  default_dose:25,   half_life:3600,      max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F4A6")
    meds[:mitoq]          = Med.new(name: :mitoq,          interval:24,   required:24, default_dose:2.5,  half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")
    meds[:hcasein]        = Med.new(name: :hcasein,        interval:24,   required:24, default_dose:2.5,  half_life:3600*3,    max_dose:0,     dose_units: :mg,   display: :no,        display_log:false, announce:false,  emoji:"1F517")

    # additional ways to match terms
    meds[:docusate].add_match_term("docusate sodium")
    meds[:azelastine].add_match_term("azelastine spray")
    meds[:veramyst].add_match_term("veramyst spray")
    meds[:morphine_er].add_match_term("morphine (er)")
    meds[:morphine_er].add_match_term("morphine er")
    meds[:morphine_ir].add_match_term("morphine (ir)")
    meds[:morphine_ir].add_match_term("morphine ir")
    meds[:phosphatidyl_c].add_match_term("pc")
    meds[:valerian_root].add_match_term("valerian root")
    meds[:fish_eggs].add_match_term("fish egg")
    meds[:calcium_aep].add_match_term("calcium aep")
    meds[:phys_thr].add_match_term("physical")
    meds[:phys_thr].add_match_term("physical therapy")
    meds[:choline_b].add_match_term("choline")
    meds
  end
end
