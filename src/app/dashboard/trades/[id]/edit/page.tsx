import { TradeForm } from '@/components/trade-form'

export default async function EditTradePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return <TradeForm mode="edit" tradeId={id} />
}
