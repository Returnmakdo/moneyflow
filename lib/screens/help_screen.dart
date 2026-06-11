import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth.dart';
import '../theme.dart';
import '../utils/nav_back.dart';
import '../widgets/common.dart';

/// 설정 → 도움말. 화면별 사용법 카드 + 온보딩 다시 보기.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text2),
          onPressed: () => goBackOr(context, '/settings'),
        ),
        title: Text(
          '도움말',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // 온보딩 다시 보기 — primaryWeak hero 카드.
            InkWell(
              onTap: () => context.go('/onboarding?from=help'),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.primaryWeak,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '소개 슬라이드 다시 보기',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '핵심 기능 빠르게 훑어보기',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.text2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 22, color: AppColors.primaryStrong),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const _GroupTitle('처음이라면'),
            const SizedBox(height: 10),
            const _GuideCard(
              icon: Icons.flag_outlined,
              title: '추천 시작 순서',
              points: [
                '1. 자산 탭에서 통장부터 추가하고, 지금 통장 잔고를 시작잔액에 적어주세요',
                '2. 같은 자산 탭에서 신용카드도 추가 — 결제일·결제계좌를 함께 정해주세요',
                '3. 거래내역 화면 오른쪽 아래 + 버튼으로 지출·수입을 입력하기 시작해요',
                '4. 카드로 결제했으면 [신용카드]를 누르고 어떤 카드인지 골라주세요 (현금/이체는 [내 계좌])',
                '5. 카드 결제일이 되면 자산 탭에 빨간 안내가 떠요 — 명세서 청구액만 적어주면 끝',
              ],
            ),
            const _GuideCard(
              icon: Icons.account_balance_wallet_outlined,
              title: '총자산이 어떻게 계산되나요?',
              points: [
                '총자산 = 모든 통장 잔고 합 − 카드 미정산 (아직 안 갚은 카드값)',
                '카드를 긁는 순간부터 미정산이 늘어서 총자산이 미리 줄어들어요',
                '결제일에 통장에서 빠질 땐 "통장 −, 미정산 −"라 총자산은 변동이 없어요',
                '이렇게 카드값을 미리 반영해야 "내가 정말 쓸 수 있는 돈"이 정확해져요',
              ],
            ),
            const SizedBox(height: 16),
            const _GroupTitle('각 화면 사용법'),
            const SizedBox(height: 10),
            const _GuideCard(
              icon: Icons.dashboard_outlined,
              title: '대시보드',
              points: [
                '이번 달 얼마 썼는지, 지난달이랑 비교해서 한눈에 보여드려요',
                '카테고리 옆 항목을 누르면 그 카테고리 거래만 모아볼 수 있어요',
                '이번 달 어디에 많이 썼는지 자주 쓴 태그 상위 10개를 알려드려요',
                '태그를 누르면 같은 태그가 붙은 거래만 모아볼 수 있어요',
              ],
            ),
            const _GuideCard(
              icon: Icons.receipt_long_outlined,
              title: '거래내역',
              points: [
                '오른쪽 아래 + 버튼을 누르면 거래를 추가할 수 있어요',
                '기간·카테고리·검색·금액 범위로 원하는 거래만 추려볼 수 있어요',
                '거래를 누르면 바로 수정할 수 있어요',
                '월세·월급 같은 정기 거래가 빠진 달엔 위쪽 안내에서 한 번에 등록해드려요',
              ],
            ),
            const _GuideCard(
              icon: Icons.savings_outlined,
              title: '예산',
              points: [
                '카테고리마다 한 달 예산을 정해두면 얼마나 썼는지 막대로 보여드려요',
                '예산의 80%를 넘으면 주황, 100%를 넘으면 빨강으로 바뀌어요',
                '예산은 매달 새로 쓰는 지출 기준이에요. 자동이체처럼 매달 똑같이 나가는 돈은 빼고 계산돼요',
              ],
            ),
            const _GuideCard(
              icon: Icons.account_balance_outlined,
              title: '자산',
              points: [
                '통장과 신용카드를 한곳에 모아서 흐름을 추적해요',
                '맨 위 총자산은 "통장 잔고 합 − 아직 안 갚은 카드값"으로 계산돼요',
                '카드 이름 옆 작은 날짜(예: 4.7 ~ 5.6)는 다음 결제일에 청구될 사용기간이에요',
                '카드를 누르면 그 사용기간 거래만 모아서 보여드려요',
                '결제일이 지났는데 카드값 등록이 안 됐으면 빨간 안내가 떠요 — 눌러서 청구액 입력하면 끝',
              ],
            ),
            const _GuideCard(
              icon: Icons.repeat,
              title: '정기 거래',
              points: [
                '구독료·월세처럼 매달 나가는 지출이나 월급·이자처럼 매달 들어오는 수입을 미리 등록해두세요',
                '등록해두면 도래일에 자동으로 거래로 추가되고 자산에 반영돼요. 따로 누를 거 없어요',
                '직접 미래 일자 거래를 등록한 경우에도 그 날짜가 되어야 자산에 반영돼요',
                '정기 거래 정보를 바꾸면 다음 자동 등록부터 반영돼요. 이미 등록된 거래를 바꾸려면 거래내역에서 직접 수정해주세요',
                '거래를 삭제하면 그 달엔 자동으로 다시 등록되지 않아요 (다음 달부턴 다시 자동 등록)',
                '다음 달부터도 영구히 안 받고 싶으면 정기 거래 항목 자체를 *비활성*으로 두거나 삭제해주세요',
                '설정 → 정기 거래 관리에서 정기지출과 정기수입을 따로 관리할 수 있어요',
              ],
            ),
            const _GuideCard(
              icon: Icons.insights_outlined,
              title: '분석',
              points: [
                '"이번 달 분석하기"를 누르면 AI가 소비 패턴을 짚어드려요',
                '요약·패턴·예산·제안 네 장을 좌우로 넘기면서 볼 수 있어요',
                '한 번 분석한 결과는 저장돼서 다음에 들어와도 바로 보여드려요',
                '거래를 추가하거나 고치면 저장된 결과가 초기화되고 "다시 분석"으로 새로 받아볼 수 있어요',
              ],
            ),
            const SizedBox(height: 16),
            const _GroupTitle('자주 묻는 질문'),
            const SizedBox(height: 10),
            const _GuideCard(
              icon: Icons.help_outline,
              title: '카테고리나 태그를 바꾸고 싶어요',
              points: [
                '설정 → 카테고리 관리에서 자유롭게 추가하거나 이름을 바꿀 수 있어요',
                '이미 사용 중인 카테고리는 거기에 묶인 거래를 먼저 정리해야 지울 수 있어요',
              ],
            ),
            const _GuideCard(
              icon: Icons.help_outline,
              title: '다른 가계부에서 데이터를 옮기고 싶어요',
              points: [
                '설정 → 데이터 가져오기에서 양식 파일을 먼저 받아보세요',
                '엑셀에서 열어 카드사 명세서를 양식에 맞게 정리해주세요',
                '저장한 다음 가져오기에서 파일만 고르면 끝이에요',
                '처음 보는 카테고리나 태그가 있으면 알아서 추가해드려요',
              ],
            ),
            const _GuideCard(
              icon: Icons.help_outline,
              title: '내 거래를 파일로 백업하고 싶어요',
              points: [
                '설정 → CSV 내보내기에서 모든 거래를 한 번에 받을 수 있어요',
                '엑셀이나 구글 시트에서 바로 열려요',
                '같은 양식이라 나중에 그대로 다시 가져와서 복원할 수 있어요',
              ],
            ),
            const _GuideCard(
              icon: Icons.help_outline,
              title: '잔여할부는 어떻게 등록해요?',
              points: [
                '카드사가 매달 청구하는 할부금은 설정 → 정기 거래에서 정기지출로 등록해주세요',
                '결제수단은 [신용카드]를 누르고 그 카드를 골라요. 등록 일자는 카드 사용기간 마감일로 잡아주세요',
                '등록 일자를 카드 결제일(예: 20일)로 두면 다음 사용기간으로 넘어가서 그 달 청구액에 안 잡혀요',
                '활성 상태면 매달 자동으로 거래로 들어가고 카드 사용기간 합계에 더해져요',
              ],
            ),
            const _GuideCard(
              icon: Icons.help_outline,
              title: '친구한테 받은 1/N 정산은 어떻게 처리해요?',
              points: [
                '카드 결제 거래는 명세서에 찍힌 전체 금액 그대로 등록해주세요',
                '친구한테 받은 돈은 따로 수입으로 추가하면 카드 청구액과 통장 흐름이 모두 정확해져요',
                '본인 부담만 적어두면 카드 사용기간 합계가 명세서랑 안 맞게 돼요',
              ],
            ),
            const _GuideCard(
              icon: Icons.help_outline,
              title: '카드 사용기간 합계와 미정산이 왜 달라요?',
              points: [
                '두 숫자는 보여드리는 의미가 달라서 다르게 나올 수 있어요',
                '사용기간 합계는 다음 결제일에 청구될 기간(예: 4.7 ~ 5.6)에 쓴 카드값이에요',
                '미정산은 지금까지 쓴 카드값 중 아직 통장에서 안 빠진 모든 금액이에요',
                '지난 결제일에 다 갚은 상태라면 "미정산 = 이번 사용기간 합계 + 그 이후 새로 쓴 금액" 이 돼요',
              ],
            ),
            if (AuthService.aiBetaEnabled)
              const _GuideCard(
                icon: Icons.help_outline,
                title: 'AI 분석은 얼마나 자주 새로 만들어져요?',
                points: [
                  '한 번 분석하면 결과를 저장해뒀다가 다시 들어와도 바로 보여드려요',
                  '그 달의 거래를 추가하거나 고치거나 지우면 저장된 결과가 자동으로 비워져요',
                  '비워진 뒤엔 "이번 달 분석하기"나 "다시 분석"을 눌러서 새로 받아볼 수 있어요',
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.text2,
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.icon,
    required this.title,
    required this.points,
  });
  final IconData icon;
  final String title;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryWeak,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final p in points) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 7),
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.text3,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.text,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
