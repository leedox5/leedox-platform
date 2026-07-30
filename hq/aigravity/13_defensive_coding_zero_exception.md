# 13. 런타임 예외 제로(Zero-Exception)를 위한 디펜시브 코딩 & 자율 검증 루프

> **Phase 4: 자율 디버깅 & 자율 PR/Merge 배포 파이프라인**  
> **Key Objective**: `ProductContentController`와 `ContentMeta`에서 발생할 수 있는 Nil Pointer 예외를 방어하는 런타임 가드(`if phase[:range]`) 기법과, 모킹 없는 100% 그린 테스트 자율 검증 루프를 학습한다.

---

## 📖 1. 런타임 예외 예방 (Defensive Guard)

외부 입력값이나 메타데이터 파일(`content_meta.yml`)의 속성이 일시적으로 누락되더라도 서비스가 500 에러로 다운되지 않도록 **디펜시브 코딩 가드**를 적용합니다.

```ruby
# ProductContentController 예시
def chapters_by_phase(phase)
  return [] unless phase[:range]
  chapters.select { |ch| phase[:range].cover?(ch[:id].to_i) }
end
```

---

## 🔤 2. Core English Definition

> **Core English Definition**: *Defensive Guard & No-Mock Testing*  
> - **Simple Definition**: Writing fail-safe condition checks to protect live applications from null errors while using real integration tests instead of fake test mocks.  
> - **Practical Meaning**: 예외 상황에서도 서비스가 멈추지 않도록 가드를 치고, 가짜 객체(Mock) 없이 실제 DB와 레코드 데이터로 시스템 정합성을 완전 검증하는 테스트 개발 기법.
