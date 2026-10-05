import Foundation

extension Builtins {
    static let english: [Prompt] = {
        let entries: [(String,String,String)] = [
            ("Continue to completion","Everyday","Continue the current task until it is complete and verified. Try to resolve problems as they arise. Finish with a brief account of the result and verification."),
            ("Report progress","Everyday","Briefly explain what is done, what remains, current blockers, and the next step."),
            ("Summarize this task","Everyday","Summarize the goal, completed work, key decisions, unresolved issues, and next steps from this conversation so we can resume later."),
            ("Plan the next steps","Everyday","List the three to five most useful next actions for this task, ordered by priority. Give the purpose and completion criteria for each."),
            ("Explain simply","Everyday","Explain in plain, concise English. Start with the conclusion, then the main reasons. Use a concrete example where helpful."),
            ("Find problems","Development","Inspect the current implementation for real problems, rank them by impact, and recommend concrete fixes."),
            ("Run verification","Development","Run the checks relevant to the current changes, fix failures, and report what passed and any remaining limitations."),
            ("Explain the code","Development","Explain the code under discussion: its purpose, main flow, inputs, outputs, dependencies, and likely failure points. Refer to concrete code."),
            ("Review code","Development","Review the current changes for correctness, regressions, error handling, and missing edge cases. Lead with findings and include location, trigger, and impact for each."),
            ("Debug the issue","Development","Use the error and code to identify the root cause. Form a testable hypothesis, run a focused check, fix it, and verify the original issue and related regressions."),
            ("Create a minimal reproduction","Development","Reduce this issue to a repeatable minimal example. Document the environment, steps, expected and actual behavior, and how to verify a fix."),
            ("Simplify the implementation","Development","Simplify this implementation while preserving behavior and interface compatibility. Reduce duplication and unnecessary abstractions, then verify the relevant behavior."),
            ("Test edge cases","Development","Identify important uncovered edge cases and add meaningful tests for high-risk behavior. Avoid tests that merely repeat implementation details."),
            ("Diagnose performance","Development","Investigate performance bottlenecks. Separate evidence from hypotheses, measure the most plausible bottleneck first, and propose verifiable improvements."),
            ("Design an interface","Development","Design a clear interface for this feature, including parameters, results, errors, compatibility, and usage examples. Prefer the simplest design that meets the requirements."),
            ("Improve the README","Development","Improve this project's README with purpose, installation, usage, configuration, troubleshooting, and verification. Base it on the actual implementation and distinguish unfinished features."),
            ("Polish the writing","Writing","Polish this text while preserving its facts and meaning. Improve logic, transitions, and clarity in natural, concise English. Do not add unsupported claims."),
            ("Write a concise summary","Writing","Condense this content while retaining the conclusion, key evidence, limitations, and next steps. Avoid repetitive background and state material uncertainty."),
            ("Create an outline","Writing","Create a clear outline for this topic. Identify what the reader needs to learn first, then arrange sections and their key arguments."),
            ("Draft an email","Writing","Turn this discussion into a ready-to-use email draft with a clear purpose, necessary context, request, and next steps. Keep it polite and concise. Draft only; do not send."),
            ("Make it conversational","Writing","Rewrite this text in natural spoken English while preserving meaning, numbers, and key information. Reduce formal filler and difficult jargon."),
            ("Translate into Chinese","Translation","Translate this content into natural Chinese, preserving formatting, code, and numbers. Retain original technical terms where useful and do not add or omit facts."),
            ("Translate into English","Translation","Translate this content into clear, natural English while preserving tone, formatting, and technical meaning. Briefly flag ambiguities."),
            ("Create a bilingual version","Translation","Create a Chinese–English version of this text with corresponding paragraphs. Preserve terminology, numbers, and structure to make comparison easy."),
            ("Compare the options","Analysis","Compare the options against requirements, cost, reliability, maintenance, and risk. Recommend an option with its conditions of use, distinguishing evidence from inference."),
            ("Clarify requirements","Analysis","Extract goals, user scenarios, scope, constraints, and acceptance criteria from the current description. Identify ambiguities that materially affect implementation and ask only necessary questions."),
            ("Check the facts","Analysis","Check the important facts and conclusions in this content using primary sources when current information is needed. Distinguish verified, disputed, and unsupported claims and cite sources."),
            ("Synthesize the research","Analysis","Synthesize the research so far: main findings, evidence quality, differences between options, and open questions. Give conditional recommendations and cite original sources."),
            ("Write meeting notes","Work","Turn the discussion into meeting notes with topics, decisions, actions, owners, and dates. Mark unknown owners or dates as to be confirmed."),
            ("Create an action list","Work","Turn this discussion into a prioritized action list with deliverables, dependencies, and completion criteria. Do not invent owners or deadlines."),
            ("Review SQL","Data","Review this SQL for filters, join relationships, aggregation grain, null handling, and double counting. Explain issues and corrections using the actual table schema."),
            ("Check data quality","Data","Check the data for completeness, duplicates, outliers, definitions, and freshness. Explain how issues affect conclusions and provide reproducible checks.")
        ] + extraEntries.map { ($0.enTitle,$0.enCategory,$0.enBody) }
        return entries.enumerated().map { i,e in
            Prompt(id:UUID(uuidString:String(format:"4A430002-0000-4000-8000-%012d",i+1))!,title:e.0,body:e.2,category:e.1,pinned:i<2,language:.en,source:i<32 ? "JustClick / prompts.chat" : "best-prompts · adapted",sourceURL:i<32 ? "https://prompts.chat/" : "https://github.com/xstongxue/best-prompts/blob/main/prompts/"+extraEntries[i-32].file)
        }
    }()
    struct Extra {
        let title:String; let category:String; let body:String
        let enTitle:String; let enCategory:String; let enBody:String; let file:String
    }
    static let extraEntries: [Extra] = [
        Extra(title:"技术方案设计",category:"开发",body:"请根据当前需求设计可落地的技术方案：先确认目标与约束，再说明技术选型、模块职责、接口、数据模型和关键权衡，最后列出实现顺序与验证方法。缺少的信息明确标注，不假设需求已经获得确认。",enTitle:"Design a technical solution",enCategory:"Development",enBody:"Design an implementable solution for the current requirements. Establish goals and constraints, then explain technology choices, module responsibilities, interfaces, data models, and trade-offs. Finish with implementation order and verification. Flag missing information without assuming requirements have been approved.",file:"dev-design-prompt.md"),
        Extra(title:"按方案实现",category:"开发",body:"请依据当前已确认的方案实现功能：检查项目结构与依赖，按模块拆分任务，编写代码与必要的错误处理，运行相关验证。交付时说明改动、运行方法、测试结果和剩余限制。",enTitle:"Implement the plan",enCategory:"Development",enBody:"Implement the currently agreed plan. Inspect project structure and dependencies, divide work by module, implement the code and necessary error handling, and run relevant checks. Report changes, how to run them, test results, and remaining limitations.",file:"dev-implementation-prompt.md"),
        Extra(title:"生成周报",category:"办公",body:"请把当前工作记录整理为周报，分为本周完成、进行中、下周计划、问题与风险。保留已有数字和事实，每项写明产出或影响；未知日期、负责人和进度标为待确认，不编造业绩。",enTitle:"Write a weekly update",enCategory:"Work",enBody:"Turn the current work notes into a weekly update with Completed, In progress, Next week, and Issues and risks. Preserve known figures and facts; describe outcomes or impact. Mark unknown dates, owners, and progress as unconfirmed rather than inventing results.",file:"doc-weekly-report-prompt.md"),
        Extra(title:"项目复盘",category:"办公",body:"请根据当前项目记录整理复盘：背景与目标、主要工作、可证实的成果、问题及根因、可复用经验、下一步改进。区分实际证据与推断，用具体行动替代空泛建议。",enTitle:"Review the project outcomes",enCategory:"Work",enBody:"Create a retrospective from the current project notes: context and goals, work completed, evidenced outcomes, problems and root causes, reusable lessons, and improvements. Separate evidence from inference and propose specific actions.",file:"doc-summary-report-prompt.md"),
        Extra(title:"梳理代码项目",category:"开发",body:"请基于当前仓库的 README、目录、依赖和关键入口，整理项目概述、模块划分、技术栈、运行方式及核心接口。每项注明依据，信息不足处列出待补充内容，不凭目录名编造功能。",enTitle:"Map the codebase",enCategory:"Development",enBody:"Use the current repository's README, directories, dependencies, and entry points to describe its purpose, modules, stack, setup, and key interfaces. Identify evidence and missing information; do not invent functionality from directory names alone.",file:"codegen-project-overview-prompt.md"),
        Extra(title:"简历项目描述",category:"办公",body:"请把当前项目整理为简历项目经历，说明项目目标、技术栈、本人有证据支持的职责和成果。优先使用准确的行动描述，只有已有证据时才写量化数据；未知时间和个人贡献标为待补充。",enTitle:"Describe a project for a résumé",enCategory:"Work",enBody:"Turn the current project into a résumé entry covering its goal, stack, evidenced personal responsibilities, and outcomes. Use precise action statements and quantify only supported results. Mark unknown dates or personal contributions for completion.",file:"codegen-resume-format-prompt.md"),
        Extra(title:"论文结构检查",category:"学术",body:"请检查当前论文提纲与已有研究材料的对应关系，梳理研究问题、方法、实验或论证、结果、局限与结论。指出缺少证据和章节衔接的问题，不编造实验、文献或引用。",enTitle:"Review a research outline",enCategory:"Research",enBody:"Check how the research outline maps to the available evidence. Review the question, method, experiments or argument, findings, limitations, and conclusion. Identify evidence gaps and weak transitions without inventing experiments, references, or citations.",file:"paper-write-prompt.md"),
        Extra(title:"技术文章草稿",category:"写作",body:"请根据当前材料写一篇面向目标读者的技术文章草稿。先明确主题与读者问题，再组织事实、示例和结论，给出三个准确的标题备选及排版建议。需要外部事实时核实来源，不把未经实际操作的内容写成亲测。",enTitle:"Draft a technical article",enCategory:"Writing",enBody:"Draft a technical article from the current material for its intended audience. Establish the topic and reader's problem, organize facts and examples, and conclude with practical takeaways. Suggest three accurate titles and formatting improvements. Verify external facts and never claim firsthand testing that did not happen.",file:"wechat-article-write-prompt.md")
    ]
    static let extraChinese: [Prompt] = extraEntries.enumerated().map { i,e in
        Prompt(id:UUID(uuidString:String(format:"4A430001-0000-4000-8000-%012d",i+33))!,title:e.title,body:e.body,category:e.category,language:.zh,source:"best-prompts · 改编",sourceURL:"https://github.com/xstongxue/best-prompts/blob/main/prompts/"+e.file)
    }
}
