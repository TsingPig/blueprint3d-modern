'use client'

import dynamic from 'next/dynamic'
import type { Blueprint3DAppConfig } from './Blueprint3DAppBase'
import { Blueprint3DErrorBoundary } from './Blueprint3DErrorBoundary'

const Blueprint3DAppBase = dynamic(
  () => import('./Blueprint3DAppBase').then((mod) => mod.Blueprint3DAppBase),
  { ssr: false }
)

interface Blueprint3DAppProps {
  config?: Blueprint3DAppConfig
}

export function Blueprint3DApp({ config }: Blueprint3DAppProps) {
  return (
    <Blueprint3DErrorBoundary>
      <Blueprint3DAppBase config={config} />
    </Blueprint3DErrorBoundary>
  )
}

export default Blueprint3DApp
